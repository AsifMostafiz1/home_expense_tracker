import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import 'image_download_service.dart';

/// Where a saved picture goes on everything that is not a browser.
///
/// On a phone that is the gallery: a photo saved out of a conversation is
/// looked for in Photos, next to the ones the camera took, not inside the
/// app's own folder where nothing else can reach it. On a desktop there is no
/// gallery, so it lands in Downloads under its own name.
///
/// The web has neither; see `image_saver_web.dart`.
Future<ImageSaveOutcome> saveImageBytes(Uint8List bytes, String fileName) async {
  if (Platform.isAndroid || Platform.isIOS) {
    return _saveToGallery(bytes, fileName);
  }
  return _saveToDownloads(bytes, fileName);
}

Future<ImageSaveOutcome> _saveToGallery(Uint8List bytes, String fileName) async {
  try {
    // Newer Androids and iOS grant this without asking; the older ones, and
    // anyone who has said no before, come through the prompt.
    if (!await Gal.hasAccess() && !await Gal.requestAccess()) {
      return ImageSaveOutcome.permissionDenied;
    }

    // Named without its extension: the gallery works out the format from the
    // bytes themselves and appends the matching one.
    await Gal.putImageBytes(bytes, name: _stemOf(fileName));
    return ImageSaveOutcome.saved;
  } on GalException catch (e) {
    debugPrint('Gal could not save $fileName — $e');
    return e.type == GalExceptionType.accessDenied
        ? ImageSaveOutcome.permissionDenied
        : ImageSaveOutcome.failed;
  } catch (e) {
    debugPrint('Gal could not save $fileName — $e');
    return ImageSaveOutcome.failed;
  }
}

Future<ImageSaveOutcome> _saveToDownloads(Uint8List bytes, String fileName) async {
  try {
    // Linux has no Downloads folder of its own through path_provider on every
    // desktop, so the app's documents folder stands in rather than failing.
    final Directory target =
        await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final File file = _freeName(target, fileName);
    await file.writeAsBytes(bytes);
    return ImageSaveOutcome.saved;
  } catch (e) {
    debugPrint('Could not write $fileName to disk — $e');
    return ImageSaveOutcome.failed;
  }
}

/// The name without its extension.
String _stemOf(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  return dot <= 0 ? fileName : fileName.substring(0, dot);
}

/// `photo.jpg`, or `photo (2).jpg` where that is taken — saving the same
/// picture twice should leave two files, not overwrite the first.
File _freeName(Directory dir, String fileName) {
  final String stem = _stemOf(fileName);
  final int dot = fileName.lastIndexOf('.');
  final String extension = dot <= 0 ? '' : fileName.substring(dot);

  File candidate = File('${dir.path}${Platform.pathSeparator}$fileName');
  for (int i = 2; candidate.existsSync() && i < 1000; i++) {
    candidate =
        File('${dir.path}${Platform.pathSeparator}$stem ($i)$extension');
  }
  return candidate;
}
