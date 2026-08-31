import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// A picture that lives on this device, drawn the same way on every platform.
///
/// On mobile a picked or queued picture is a real file path and `Image.file`
/// reads it. On web there is no file system: image_picker hands out a `blob:`
/// URL, `Image.file` throws by design, and the same URL has to go through
/// `Image.network` instead. Every widget that shows a not-yet-uploaded picture
/// routes through here so none of them carry that fork themselves.
class LocalImage extends StatelessWidget {
  /// A file path on mobile, a `blob:` URL on web.
  final String path;
  final double? width;
  final double? height;
  final BoxFit? fit;

  const LocalImage(
    this.path, {
    super.key,
    this.width,
    this.height,
    this.fit,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(path, width: width, height: height, fit: fit);
    }
    return Image.file(File(path), width: width, height: height, fit: fit);
  }
}

/// The provider form of [LocalImage], for widgets that take an
/// [ImageProvider] — a `CircleAvatar`, say — rather than a widget.
ImageProvider localImageProvider(String path) =>
    kIsWeb ? NetworkImage(path) : FileImage(File(path)) as ImageProvider;
