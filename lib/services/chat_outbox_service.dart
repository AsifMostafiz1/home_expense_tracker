import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show StorageException;

import '../presentation/chat/model/outgoing_image_model.dart';
import '../presentation/chat/repository/chat_repository.dart';
import '../utils/app_constant.dart';
import '../utils/supabase_config.dart';
import 'background_sync_service.dart';
import 'connectivity_service.dart';
import 'push_notification_service.dart';
import 'supabase_storage_service.dart';

/// Messages on their way out of the group chat.
///
/// Every send goes through here — text or picture, online or not. The
/// composer hands over an [OutgoingMessage] and moves on; the outbox delivers
/// it as soon as it can, in the order it was given, and forgets it once the
/// message is in Firestore and the notification is away. Online, that is a
/// moment later and the bubble is replaced by the real message so fast the
/// eye barely catches it. Offline, the bubble stays — across restarts, the
/// queue lives on disk and pictures are copied into the app's own folder —
/// until the connection returns; if the app is not opened again, the OS job
/// in `BackgroundSyncService` runs the same [flush].
///
/// Why not lean on Firestore's own queue for text, the way expenses do?
/// Because a chat message is not done when it is written: the people it is
/// for get a push notification, worked out from the mentions and the reply
/// at send time. Keeping the whole send — write and notification — as one
/// unit here means an offline message still notifies its recipients when it
/// finally goes, wherever that happens.
class ChatOutboxService extends GetxController implements GetxService {
  final SupabaseStorageService _storage;
  final ChatRepository? _repositoryOverride;
  final ConnectivityService? _connectivity;

  /// Dependencies default to the app's own — the ones GetX holds. The
  /// background sync, which runs with no GetX, hands in its own and no
  /// connectivity service at all.
  ChatOutboxService({
    SupabaseStorageService? storage,
    ChatRepository? repository,
    ConnectivityService? connectivity,
  })  : _storage = storage ?? SupabaseStorageService(),
        _repositoryOverride = repository,
        _connectivity = connectivity;

  ChatRepository get _repository =>
      _repositoryOverride ?? Get.find<ChatRepository>();

  final List<OutgoingMessage> _items = [];
  StreamSubscription<bool>? _onlineSubscription;
  bool _flushing = false;

  /// Oldest first — the order they were sent, and the order they go out.
  List<OutgoingMessage> get items => List<OutgoingMessage>.unmodifiable(_items);
  int get length => _items.length;
  bool get isEmpty => _items.isEmpty;
  bool get isNotEmpty => _items.isNotEmpty;

  /// Whether the queue is being worked right now — what the bubbles show as
  /// "sending" rather than "waiting".
  bool get isDelivering => _flushing;

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
      final String? raw = prefs.getString(AppConstant.keyChatOutbox);
      if (raw == null || raw.isEmpty) return;

      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      _items
        ..clear()
        ..addAll(list.map((dynamic entry) =>
            OutgoingMessage.fromJson(Map<String, dynamic>.from(entry as Map))));
    } catch (e) {
      debugPrint('ChatOutbox: failed to load — $e');
    }
    update();
  }

  Future<void> _save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppConstant.keyChatOutbox,
      jsonEncode(_items.map((item) => item.toJson()).toList()),
    );
  }

  /// Takes a message off the composer's hands. [image], when given, is copied
  /// into the outbox's own folder first — image_picker's temp files are the
  /// OS's to sweep. Delivery starts at once if there is a connection.
  Future<OutgoingMessage> enqueue({
    required String localId,
    required String text,
    File? image,
    double? imageWidth,
    double? imageHeight,
    String? replyToId,
    String? replyToText,
    String? replyToSenderName,
    String? replyToSenderPhone,
    String? replyToImage,
    required String senderName,
    required String senderPhone,
    String? senderImage,
    required String pushTitle,
    required String pushBody,
    List<String>? pushTargets,
    Map<String, String> pushData = const {},
  }) async {
    String? storedPath;
    if (image != null) {
      final Directory dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/pending_chat',
      );
      if (!await dir.exists()) await dir.create(recursive: true);
      storedPath = '${dir.path}/$localId${_storage.extensionOf(image.path)}';
      await image.copy(storedPath);
    }

    final OutgoingMessage item = OutgoingMessage(
      localId: localId,
      text: text,
      imagePath: storedPath,
      imageWidth: imageWidth,
      imageHeight: imageHeight,
      replyToId: replyToId,
      replyToText: replyToText,
      replyToSenderName: replyToSenderName,
      replyToSenderPhone: replyToSenderPhone,
      replyToImage: replyToImage,
      senderName: senderName,
      senderPhone: senderPhone,
      senderImage: senderImage,
      pushTitle: pushTitle,
      pushBody: pushBody,
      pushTargets: pushTargets,
      pushData: pushData,
      queuedAt: DateTime.now(),
    );
    _items.add(item);
    await _save();
    update();

    if (_connectivity?.isOffline ?? false) {
      // Should the app be closed before the connection returns, the OS
      // finishes the job — see BackgroundSyncService.
      BackgroundSyncService.schedule();
    } else {
      flush();
    }
    return item;
  }

  /// Puts a failed message back in the queue and has another go.
  Future<void> retry(OutgoingMessage item) async {
    item.failed = false;
    await _save();
    update();
    flush();
  }

  /// Drops a message that never went — the sender's call, never the outbox's.
  Future<void> discard(OutgoingMessage item) async {
    _items.remove(item);
    await _deleteFile(item.imagePath);
    await _save();
    update();
  }

  /// Delivers everything that is waiting, oldest first. Stops at the first
  /// sign of network trouble and leaves the rest for the next connection;
  /// anything that fails for a reason a retry will not fix is marked and
  /// stepped over. Returns true when nothing is left waiting afterwards.
  Future<bool> flush() async {
    if (_flushing) return _items.isEmpty;
    // Known to be offline: nothing to gain by trying, and a write made now
    // would land in Firestore's queue with its notification lost. Wait.
    if (_connectivity?.isOffline ?? false) return _items.isEmpty;
    _flushing = true;
    update();

    try {
      while (true) {
        final OutgoingMessage? next =
            _items.firstWhereOrNull((item) => !item.failed);
        if (next == null) break;

        try {
          await _deliver(next);
        } catch (e) {
          if (_isTransient(e)) {
            // The network, not the message. Wait for the next connection —
            // and let the connectivity service know something is off, since
            // a data plan that has run out looks connected until it fails.
            debugPrint('ChatOutbox: delivery paused — $e');
            _connectivity?.probe();
            BackgroundSyncService.schedule();
            break;
          }
          debugPrint('ChatOutbox: delivery failed — $e');
          next.failed = true;
          await _save();
          update();
        }
      }
    } finally {
      _flushing = false;
      update();
    }
    return _items.where((item) => !item.failed).isEmpty;
  }

  Future<void> _deliver(OutgoingMessage item) async {
    String? imageUrl;
    if (item.hasImage) {
      final File file = item.file!;
      if (!await file.exists()) {
        throw const FileSystemException('picture is gone from the outbox');
      }
      imageUrl = await _storage
          .uploadFile(file, folder: SupabaseConfig.folderChat)
          .timeout(const Duration(seconds: 60));
    }

    // Dropped before the write: from here on Firestore's own local echo puts
    // the message on screen, and two copies of it would show otherwise.
    _items.remove(item);
    await _save();
    update();

    try {
      await _repository.sendMessage(
        item.text,
        item.senderName,
        item.senderPhone,
        senderImage: item.senderImage,
        replyTo: item.replyTo,
        imageUrl: imageUrl,
        imageWidth: item.imageWidth,
        imageHeight: item.imageHeight,
      );
    } catch (e) {
      // The write did not take. Put the message back where it was so nothing
      // is lost, then let the caller decide whether that was the network.
      _items.insert(0, item);
      await _save();
      update();
      // The picture is up but nothing points at it.
      if (imageUrl != null) await _storage.deleteByPublicUrl(imageUrl);
      rethrow;
    }

    await _deleteFile(item.imagePath);

    // Best effort, bounded, and never a reason to keep the message: it is in
    // the thread already, notification or not.
    try {
      await PushNotificationService()
          .sendPushNotification(
            title: item.pushTitle,
            body: item.pushBody,
            targetPhones: item.pushTargets,
            imageUrl: imageUrl,
            data: item.pushData,
          )
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('ChatOutbox: notification not sent — $e');
    }
  }

  /// Errors that mean "no usable network right now" rather than "this message
  /// cannot be sent" — the difference between waiting and giving up.
  bool _isTransient(Object e) {
    if (e is SocketException ||
        e is TimeoutException ||
        e is HandshakeException ||
        e is http.ClientException) {
      return true;
    }
    if (e is StorageException) {
      final int code = int.tryParse(e.statusCode ?? '') ?? 0;
      return code == 0 || code >= 500;
    }
    if (e is FirebaseException) {
      return e.code == 'unavailable' || e.code == 'deadline-exceeded';
    }
    return false;
  }

  Future<void> _deleteFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final File file = File(path);
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('ChatOutbox: could not delete $path — $e');
    }
  }

  @override
  void onClose() {
    _onlineSubscription?.cancel();
    super.onClose();
  }
}
