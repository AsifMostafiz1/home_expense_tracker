import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'image_download_service.dart';

/// Saving a picture in a browser, which has no gallery and no file system:
/// hand the bytes to the browser and let it do what it does with a download.
///
/// The bytes are wrapped in a blob of this page's own making rather than
/// pointing a link at the storage bucket. An anchor's `download` attribute is
/// only honoured same-origin — aimed across origins it is ignored, and the
/// photo opens in a new tab instead of being saved, which is exactly what the
/// person tapping "save" did not ask for.
///
/// There is no permission to ask for and no way to know where it landed, so
/// this never reports anything but [ImageSaveOutcome.saved] or a failure.
Future<ImageSaveOutcome> saveImageBytes(Uint8List bytes, String fileName) async {
  String? objectUrl;
  try {
    final web.Blob blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: _mimeOf(fileName)),
    );
    objectUrl = web.URL.createObjectURL(blob);

    final web.HTMLAnchorElement link = web.HTMLAnchorElement()
      ..href = objectUrl
      ..download = fileName
      ..style.display = 'none';

    // In the document rather than loose: Firefox ignores a click on an anchor
    // that was never attached.
    web.document.body?.appendChild(link);
    link.click();
    link.remove();

    // Held for a while before letting go. The browser reads the blob after
    // the click returns, and revoking it out from under a download in
    // progress cancels the download.
    _revokeLater(objectUrl);
    return ImageSaveOutcome.saved;
  } catch (e) {
    if (objectUrl != null) web.URL.revokeObjectURL(objectUrl);
    debugPrint('Browser would not download $fileName — $e');
    return ImageSaveOutcome.failed;
  }
}

void _revokeLater(String objectUrl) {
  Future<void>.delayed(
    const Duration(seconds: 30),
    () => web.URL.revokeObjectURL(objectUrl),
  );
}

/// What the browser should call the bytes. It names the saved file from the
/// `download` attribute, but a type it recognises keeps it from second
/// guessing the extension.
String _mimeOf(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  final String extension =
      dot < 0 ? '' : fileName.substring(dot).toLowerCase();

  return switch (extension) {
    '.png' => 'image/png',
    '.gif' => 'image/gif',
    '.webp' => 'image/webp',
    '.heic' || '.heif' => 'image/heic',
    '.bmp' => 'image/bmp',
    _ => 'image/jpeg',
  };
}
