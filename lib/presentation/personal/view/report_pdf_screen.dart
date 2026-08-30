import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:printing/printing.dart';

import '../../../common/widgets/custom_app_bar.dart';

/// The finished file, with the platform's own share and print behind it.
class ReportPdfScreen extends StatelessWidget {
  final Uint8List bytes;
  final String fileName;

  const ReportPdfScreen({
    super.key,
    required this.bytes,
    required this.fileName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: CustomAppBar(title: 'report_pdf'.tr),
      body: PdfPreview(
        build: (_) async => bytes,
        pdfFileName: fileName,
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
        scrollViewDecoration:
            BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor),
      ),
    );
  }
}
