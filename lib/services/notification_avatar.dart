import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// The pictures a chat notification is drawn with — the sender's face, and
/// the photo they sent.
///
/// Android will not fetch either one for us: a notification carries bitmaps,
/// not URLs, so whichever isolate raises the notification has to have the
/// bytes in hand before it calls `show`. That is the whole job here, and the
/// reason it is worth caching: a message from the same person a minute later
/// must not spend another network round trip on a face this device has
/// already seen.
///
/// Two caches, because a push arrives in two different places. The map serves
/// a run of messages inside one isolate; the file serves the next background
/// isolate, which is born with nothing and dies again a second later. Both
/// are best effort — a picture that cannot be fetched is a notification
/// without a picture, never a notification that did not arrive.
class NotificationAvatar {
  const NotificationAvatar._();

  static final Map<String, Uint8List> _memory = {};

  /// A background message handler is not given long by the system, and a
  /// notification that arrives late is worth more than one that arrives with
  /// a face. Short on purpose.
  static const Duration _timeout = Duration(seconds: 6);

  /// What a profile picture is allowed to weigh. The uploader compresses well
  /// under this; anything above it is not an avatar and does not belong in a
  /// notification.
  static const int _maxAvatarBytes = 2 * 1024 * 1024;

  /// A sent photo is a photo, so it gets more room than a face.
  static const int _maxPhotoBytes = 8 * 1024 * 1024;

  /// The bytes behind [url], or null when there is nothing usable there.
  ///
  /// [large] asks for the photo budget rather than the avatar one.
  static Future<Uint8List?> bytesFor(String? url, {bool large = false}) async {
    if (kIsWeb) return null;

    final String key = (url ?? '').trim();
    if (key.isEmpty || !key.startsWith('http')) return null;

    final Uint8List? remembered = _memory[key];
    if (remembered != null) return remembered;

    final File? file = await _cacheFile(key);
    if (file != null) {
      try {
        if (await file.exists()) {
          final Uint8List saved = await file.readAsBytes();
          if (saved.isNotEmpty) return _memory[key] = saved;
        }
      } catch (e) {
        debugPrint('NotificationAvatar: could not read the cached copy — $e');
      }
    }

    final int limit = large ? _maxPhotoBytes : _maxAvatarBytes;
    Uint8List? bytes;
    try {
      final http.Response response =
          await http.get(Uri.parse(key)).timeout(_timeout);
      final Uint8List body = response.bodyBytes;
      if (response.statusCode == 200 && body.isNotEmpty && body.length <= limit) {
        bytes = body;
      }
    } catch (e) {
      debugPrint('NotificationAvatar: could not fetch $key — $e');
    }

    // Only a hit is remembered. A miss is usually the network rather than the
    // picture, and caching it would keep the face off every notification for
    // as long as this isolate lives.
    if (bytes == null) return null;

    _memory[key] = bytes;
    if (file != null) {
      try {
        await file.writeAsBytes(bytes, flush: true);
      } catch (e) {
        debugPrint('NotificationAvatar: could not cache $key — $e');
      }
    }
    return bytes;
  }

  static Future<File?> _cacheFile(String url) async {
    try {
      final Directory dir = Directory(
          '${(await getTemporaryDirectory()).path}/notification_avatars');
      if (!await dir.exists()) await dir.create(recursive: true);
      return File('${dir.path}/${_fileName(url)}');
    } catch (e) {
      debugPrint('NotificationAvatar: no cache directory — $e');
      return null;
    }
  }

  /// A name, not a digest: this is a cache key for a handful of files in the
  /// temporary directory, so a cheap hash the URL length disambiguates is
  /// enough, and it saves pulling in a crypto dependency for it.
  static String _fileName(String url) =>
      '${url.hashCode.toUnsigned(32).toRadixString(16)}_${url.length}';
}
