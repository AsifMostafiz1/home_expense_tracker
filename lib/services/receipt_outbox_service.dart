import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../presentation/expense/repository/expense_repository.dart';
import '../utils/app_constant.dart';
import '../utils/supabase_config.dart';
import 'background_sync_service.dart';
import 'connectivity_service.dart';
import 'supabase_storage_service.dart';

/// A receipt picked while offline, waiting for its upload.
class PendingReceipt {
  final String expenseId;

  /// The app's own copy of the picture — see [ReceiptOutboxService.enqueue].
  final String path;

  /// The receipt this one replaces, deleted from storage once the new URL is
  /// on the expense. Null for a first receipt.
  final String? replacesUrl;

  const PendingReceipt({
    required this.expenseId,
    required this.path,
    this.replacesUrl,
  });

  Map<String, dynamic> toJson() => {
        'expenseId': expenseId,
        'path': path,
        'replacesUrl': replacesUrl,
      };

  factory PendingReceipt.fromJson(Map<String, dynamic> json) => PendingReceipt(
        expenseId: json['expenseId'] as String,
        path: json['path'] as String,
        replacesUrl: json['replacesUrl'] as String?,
      );
}

/// Receipts whose upload has to wait for a connection.
///
/// The expense itself is saved the moment it is entered — Firestore keeps its
/// own queue of writes and delivers them when the network returns. A receipt
/// photo has no such queue: it goes to Supabase, which is a plain HTTP upload.
/// So the picked file is copied into the app's own folder (image_picker hands
/// out temp files the OS is free to sweep) and remembered against the expense
/// id. [flush] runs once there is a connection: it uploads what is waiting,
/// points the expense at the URL, and forgets the file.
class ReceiptOutboxService extends GetxController implements GetxService {
  final SupabaseStorageService _storage;
  final ExpenseRepository? _repositoryOverride;
  final Map<String, PendingReceipt> _pending = {};

  /// Both dependencies default to the app's own — the ones GetX holds. The
  /// background sync, which runs with no GetX at all, hands in its own.
  ReceiptOutboxService({
    SupabaseStorageService? storage,
    ExpenseRepository? repository,
  })  : _storage = storage ?? SupabaseStorageService(),
        _repositoryOverride = repository;

  StreamSubscription<bool>? _onlineSubscription;
  bool _flushing = false;

  final StreamController<void> _synced = StreamController<void>.broadcast();

  /// Fires after a [flush] that changed something — the expense list re-reads
  /// so the rows pick up their new URLs.
  Stream<void> get onSynced => _synced.stream;

  ExpenseRepository get _repository =>
      _repositoryOverride ?? Get.find<ExpenseRepository>();

  int get length => _pending.length;
  bool get isEmpty => _pending.isEmpty;
  bool get isNotEmpty => _pending.isNotEmpty;

  /// The local file waiting to be uploaded for [expenseId], if any.
  String? pathFor(String expenseId) => _pending[expenseId]?.path;

  Future<void> init(ConnectivityService connectivity) async {
    await load();
    _onlineSubscription = connectivity.onOnline.listen((_) => flush());
    if (connectivity.isOnline) flush();
  }

  /// Reads what is waiting from disk. Part of [init]; on its own for the
  /// background sync.
  Future<void> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(AppConstant.keyPendingReceipts);
      if (raw == null || raw.isEmpty) return;

      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      for (final dynamic entry in list) {
        final PendingReceipt item =
            PendingReceipt.fromJson(Map<String, dynamic>.from(entry as Map));
        _pending[item.expenseId] = item;
      }
    } catch (e) {
      debugPrint('ReceiptOutbox: failed to load — $e');
    }
    update();
  }

  Future<void> _save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppConstant.keyPendingReceipts,
      jsonEncode(_pending.values.map((item) => item.toJson()).toList()),
    );
  }

  /// Keeps [file] for [expenseId] until it can be uploaded. Replaces whatever
  /// was already waiting for that expense.
  Future<void> enqueue({
    required String expenseId,
    required File file,
    String? replacesUrl,
  }) async {
    final Directory dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/pending_receipts',
    );
    if (!await dir.exists()) await dir.create(recursive: true);

    final String target =
        '${dir.path}/$expenseId${_storage.extensionOf(file.path)}';

    // Re-queuing the copy we already hold (an edit saved offline again).
    if (file.path != target) {
      final PendingReceipt? previous = _pending[expenseId];
      await file.copy(target);
      if (previous != null && previous.path != target) {
        await _deleteFile(previous.path);
      }
    }

    _pending[expenseId] = PendingReceipt(
      expenseId: expenseId,
      path: target,
      // An earlier queued receipt never made it to storage, so the URL to
      // clean up is still the one it was meant to replace.
      replacesUrl: replacesUrl ?? _pending[expenseId]?.replacesUrl,
    );
    await _save();
    update();

    // Should the app be closed before the connection returns, the OS
    // finishes the upload — see BackgroundSyncService.
    BackgroundSyncService.schedule();
  }

  /// Forgets the receipt waiting for [expenseId] — the expense was deleted, or
  /// its photo removed, before the upload ever ran.
  Future<void> remove(String expenseId) async {
    final PendingReceipt? item = _pending.remove(expenseId);
    if (item == null) return;

    await _deleteFile(item.path);
    await _save();
    update();
  }

  /// Uploads everything that is waiting. Stops at the first network failure
  /// and leaves the rest for the next connection; safe to call any time.
  /// Returns true when nothing is left waiting afterwards.
  Future<bool> flush() async {
    if (_flushing || _pending.isEmpty) return _pending.isEmpty;
    _flushing = true;
    bool changed = false;

    try {
      for (final PendingReceipt item in _pending.values.toList()) {
        final File file = File(item.path);
        if (!await file.exists()) {
          // The OS, or a reinstall, took the copy. Nothing left to upload.
          await remove(item.expenseId);
          changed = true;
          continue;
        }

        // Bounded so a stalled upload cannot leave [_flushing] set for good.
        final String url = await _storage
            .uploadFile(file, folder: SupabaseConfig.folderExpense)
            .timeout(const Duration(seconds: 60));

        try {
          await _repository.updateExpense(item.expenseId, {
            'image_url': url,
            'updatedAt': DateTime.now().toIso8601String(),
          });
        } on FirebaseException catch (e) {
          if (e.code != 'not-found') rethrow;
          // The expense is gone; the picture would only be an orphan.
          await _storage.deleteByPublicUrl(url);
          await remove(item.expenseId);
          changed = true;
          continue;
        }

        await _storage.deleteByPublicUrl(item.replacesUrl);
        await remove(item.expenseId);
        changed = true;
      }
    } catch (e) {
      // Almost always "still no usable connection". Whatever is left keeps
      // waiting for the next trigger.
      debugPrint('ReceiptOutbox: flush stopped — $e');
    } finally {
      _flushing = false;
      if (changed) _synced.add(null);
    }
    return _pending.isEmpty;
  }

  Future<void> _deleteFile(String path) async {
    try {
      final File file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('ReceiptOutbox: could not delete $path — $e');
    }
  }

  @override
  void onClose() {
    _onlineSubscription?.cancel();
    _synced.close();
    super.onClose();
  }
}
