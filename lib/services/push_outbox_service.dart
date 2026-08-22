import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_constant.dart';
import 'background_sync_service.dart';
import 'connectivity_service.dart';
import 'push_notification_service.dart';

/// A notification that has not gone out yet.
class PendingPush {
  final String title;
  final String body;
  final List<String>? targetPhones;
  final Map<String, String> data;
  final String? imageUrl;

  /// Sent without a `notification` block, leaving the receiving device to
  /// decide whether to raise it — see `PushNotificationService`.
  final bool dataOnly;

  /// How many times sending has been tried and failed. Past a limit the
  /// notification is dropped: a message nobody could deliver five times is a
  /// broken message, not a slow network, and it must not jam the queue.
  int attempts;

  PendingPush({
    required this.title,
    required this.body,
    this.targetPhones,
    this.data = const {},
    this.imageUrl,
    this.dataOnly = false,
    this.attempts = 0,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        'targetPhones': targetPhones,
        'data': data,
        'imageUrl': imageUrl,
        'dataOnly': dataOnly,
        'attempts': attempts,
      };

  factory PendingPush.fromJson(Map<String, dynamic> json) => PendingPush(
        title: (json['title'] ?? '') as String,
        body: (json['body'] ?? '') as String,
        targetPhones: (json['targetPhones'] as List?)?.cast<String>(),
        data: Map<String, String>.from(
            (json['data'] as Map?) ?? const <String, String>{}),
        imageUrl: json['imageUrl'] as String?,
        dataOnly: json['dataOnly'] == true,
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      );
}

/// Push notifications for writes that were saved offline.
///
/// Firestore carries the write itself once the connection returns — an
/// announcement, an admin's correction to somebody's expense — but the
/// notification that goes with it is a plain HTTP call with no queue of its
/// own. So [send] tries at once when there is a connection and files the
/// notification here when there is not (or when the send fails); [flush]
/// sends whatever is filed once the network is back, from the app or from
/// the background job in `BackgroundSyncService`.
///
/// Chat messages do not come through here: theirs travels with the message
/// in `ChatOutboxService`, so the two cannot come apart.
class PushOutboxService extends GetxController implements GetxService {
  final ConnectivityService? _connectivity;

  /// No connectivity service in the background job — it only runs with a
  /// network, so [send] there always tries.
  PushOutboxService({ConnectivityService? connectivity})
      : _connectivity = connectivity;

  static const int _maxAttempts = 5;

  /// Whether an attempt is worth making. Not `isOnline`: that carries the
  /// verdict of a probe against an unrelated host, and one slow probe used to
  /// file every notification for later on a connection that would have
  /// carried it. With an interface up, FCM is the better authority — a real
  /// failure files the notification anyway, one line below.
  ///
  /// The background job hands in no service at all and always tries; it only
  /// runs when the OS says there is a network.
  bool get _worthTrying => _connectivity?.hasNetwork ?? true;

  final List<PendingPush> _items = [];
  StreamSubscription<bool>? _onlineSubscription;
  bool _flushing = false;

  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

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
      final String? raw = prefs.getString(AppConstant.keyPushOutbox);
      if (raw == null || raw.isEmpty) return;

      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      _items
        ..clear()
        ..addAll(list.map((dynamic entry) =>
            PendingPush.fromJson(Map<String, dynamic>.from(entry as Map))));
    } catch (e) {
      debugPrint('PushOutbox: failed to load — $e');
    }
  }

  Future<void> _save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppConstant.keyPushOutbox,
      jsonEncode(_items.map((item) => item.toJson()).toList()),
    );
  }

  /// Sends now if it can, files the notification for later if it cannot.
  /// Never throws, never blocks on the network for long: the write it goes
  /// with is already saved, and this must not hold up whatever saved it.
  Future<void> send({
    required String title,
    required String body,
    List<String>? targetPhones,
    Map<String, String> data = const {},
    String? imageUrl,
    bool dataOnly = false,
  }) async {
    final PendingPush push = PendingPush(
      title: title,
      body: body,
      targetPhones: targetPhones,
      data: data,
      imageUrl: imageUrl,
      dataOnly: dataOnly,
    );

    if (_worthTrying) {
      // Not while a flush is running: it would go out ahead of older ones.
      if (!_flushing && await _trySend(push)) return;
    }

    _items.add(push);
    await _save();
    debugPrint('PushOutbox: filed "${push.title}" for later');
    BackgroundSyncService.schedule();
    _connectivity?.probe();
  }

  Future<bool> _trySend(PendingPush push) async {
    try {
      final bool sent = await PushNotificationService().sendPushNotification(
        title: push.title,
        body: push.body,
        targetPhones: push.targetPhones,
        data: push.data,
        imageUrl: push.imageUrl,
        dataOnly: push.dataOnly,
      );
      if (!sent) push.attempts++;
      return sent;
    } catch (e) {
      debugPrint('PushOutbox: send failed — $e');
      push.attempts++;
      return false;
    }
  }

  /// Sends what is filed, oldest first. Stops at the first failure — almost
  /// always the network again — and drops anything that has failed too many
  /// times. Returns true when nothing is left waiting.
  Future<bool> flush() async {
    if (_flushing || _items.isEmpty) return _items.isEmpty;
    if (!_worthTrying) return false;
    _flushing = true;

    try {
      while (_items.isNotEmpty) {
        final PendingPush next = _items.first;
        if (await _trySend(next)) {
          _items.removeAt(0);
          await _save();
          continue;
        }
        if (next.attempts >= _maxAttempts) {
          debugPrint('PushOutbox: giving up on "${next.title}"');
          _items.removeAt(0);
          await _save();
          continue;
        }
        await _save();
        _connectivity?.probe();
        break;
      }
    } finally {
      _flushing = false;
    }
    return _items.isEmpty;
  }

  @override
  void onClose() {
    _onlineSubscription?.cancel();
    super.onClose();
  }
}
