import 'dart:isolate';
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// One photographed page: raw RGBA pixels straight from the engine, so the
/// PDF library has nothing to decode — a PNG here would be unpacked again
/// in pure Dart, pixel by pixel, on the thread the spinner runs on.
class PagePicture {
  final Uint8List rgba;
  final int width;
  final int height;

  const PagePicture(this.rgba, this.width, this.height);
}

/// Binds photographed pages into one A4 PDF, each picture the whole of its
/// page — see `ReportPage` for why the pages are pictures.
///
/// Built on another isolate: with pixels for inputs and bytes for output
/// there is nothing here that needs the UI thread, and a ten-page report is
/// forty million pixels the interface would otherwise stall on.
class ReportPdfBuilder {
  ReportPdfBuilder._();

  static Future<Uint8List> build(
    List<PagePicture> pages, {
    required String title,
    required String author,
  }) {
    return Isolate.run(() => _bind(pages, title: title, author: author));
  }

  static Future<Uint8List> _bind(
    List<PagePicture> pages, {
    required String title,
    required String author,
  }) {
    final pw.Document document = pw.Document(title: title, author: author);
    for (final PagePicture page in pages) {
      final pw.RawImage image = pw.RawImage(
        bytes: page.rgba,
        width: page.width,
        height: page.height,
      );
      document.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: pw.EdgeInsets.zero,
        build: (_) => pw.FullPage(
          ignoreMargins: true,
          child: pw.Image(image, fit: pw.BoxFit.fill),
        ),
      ));
    }
    return document.save();
  }
}
