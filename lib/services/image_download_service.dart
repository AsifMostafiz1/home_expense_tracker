import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'image_saver_io.dart'
    if (dart.library.js_interop) 'image_saver_web.dart' as saver;

/// What became of a picture somebody asked to keep.
enum ImageSaveOutcome {
  /// In the gallery on a phone, in the Downloads folder on a desktop, and
  /// wherever the browser puts a download on web.
  saved,

  /// Photo access was asked for and refused. Worth its own answer: the fix is
  /// in the system settings, not in tapping the button again.
  permissionDenied,

  /// The picture never arrived, or the device would not take it.
  failed,
}

/// Pulls a picture the app is showing down onto the device.
///
/// The bytes are fetched here — the same public URL the viewer is already
/// showing — and handed to whichever saver this platform builds with: the
/// gallery on Android and iOS, the Downloads folder on a desktop, a browser
/// download on web. See `image_saver_io.dart` and `image_saver_web.dart`.
///
/// Nothing here throws. A save is something somebody asked for while looking
/// at a photograph; the answer they want is "saved" or "not saved", and every
/// way of not saving is already a value of [ImageSaveOutcome].
class ImageDownloadService {
  const ImageDownloadService._();

  /// A picture worth waiting for, but not forever: a link that is up and not
  /// answering must not leave a spinner running on the viewer's top bar.
  static const Duration _timeout = Duration(seconds: 45);

  /// Fetches [url] and saves it, returning what happened.
  static Future<ImageSaveOutcome> saveFromUrl(String url) async {
    if (url.trim().isEmpty) return ImageSaveOutcome.failed;

    try {
      final http.Response response =
          await http.get(Uri.parse(url)).timeout(_timeout);

      if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
        debugPrint(
            'Image download: $url answered ${response.statusCode}, '
            '${response.bodyBytes.length} bytes');
        return ImageSaveOutcome.failed;
      }

      return await saver.saveImageBytes(
        response.bodyBytes,
        fileNameFor(url, contentType: response.headers['content-type']),
      );
    } catch (e) {
      debugPrint('Image download failed for $url — $e');
      return ImageSaveOutcome.failed;
    }
  }

  /// What the saved file should be called.
  ///
  /// The object's own name where the URL carries one — a photo saved twice
  /// from two devices then lands under the same name rather than under two
  /// timestamps — and a stamped fallback where it does not. The extension
  /// comes from the name when it has one and from the served content type
  /// otherwise, since a gallery sorts by it and a browser names by it.
  @visibleForTesting
  static String fileNameFor(String url, {String? contentType}) {
    // Already percent-decoded by `Uri`, and only the path: a signed URL's
    // query is a token, not part of what the picture is called.
    final Uri? uri = Uri.tryParse(url);
    final String last =
        (uri?.pathSegments.isNotEmpty ?? false) ? uri!.pathSegments.last : '';

    final String cleaned = _sanitise(last);
    final int dot = cleaned.lastIndexOf('.');
    // Only a real extension counts. A dot sitting in the middle of a name —
    // `2024.10.receipt` — is part of the name, not a format.
    final bool named =
        dot > 0 && _extensionPattern.hasMatch(cleaned.substring(dot));

    final String stem = named ? cleaned.substring(0, dot) : cleaned;
    final String extension = named
        ? cleaned.substring(dot).toLowerCase()
        : _extensionOf(contentType);

    if (stem.isEmpty) {
      return 'image_${DateTime.now().millisecondsSinceEpoch}$extension';
    }
    return '$stem$extension';
  }

  static final RegExp _extensionPattern = RegExp(r'^\.[A-Za-z0-9]{1,5}$');

  /// Keeps a name to what every file system this app runs on will take, and
  /// keeps a crafted URL from naming a path of its own or a dotfile nobody
  /// will find again.
  static String _sanitise(String name) => name
      .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^\.+'), '')
      .trim();

  static String _extensionOf(String? contentType) {
    final String type = (contentType ?? '').split(';').first.trim();
    return switch (type) {
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      'image/heic' || 'image/heif' => '.heic',
      'image/bmp' => '.bmp',
      _ => '.jpg',
    };
  }
}
