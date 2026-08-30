import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../utils/app_enums.dart';
import '../../../utils/app_ui.dart';
import '../controller/personal_controller.dart';
import '../model/personal_report.dart';
import '../model/report_pages.dart';
import '../model/subcategory.dart';
import '../widgets/report_page.dart';
import '../widgets/report_pdf_builder.dart';
import 'report_pdf_screen.dart';

/// The report, page by page, before it is a file.
///
/// Every page is drawn here as widgets at A4 proportions and scaled to the
/// phone — what is on screen is exactly what the PDF will hold, because the
/// PDF is made by photographing these very widgets. A snapshot of the
/// ledger, taken once on the way in: a report that shifted under the
/// reader while they scrolled it would not be a report.
class ReportViewScreen extends StatefulWidget {
  final ReportFilter filter;

  const ReportViewScreen({super.key, required this.filter});

  @override
  State<ReportViewScreen> createState() => _ReportViewScreenState();
}

class _ReportViewScreenState extends State<ReportViewScreen> {
  late final PersonalController _controller = Get.find<PersonalController>();
  late final PersonalReport _report = PersonalReport.of(
    widget.filter,
    _controller.transactions,
    subcategories: _controller.subcategories,
  );
  late final List<ReportPageSpec> _pages = ReportPages.plan(_report);
  late final Map<String, String> _tagNames = {
    for (final Subcategory sub in _controller.subcategories) sub.id: sub.name,
  };
  late final DateTime _generatedAt = DateTime.now();
  late final List<GlobalKey> _keys =
      List.generate(_pages.length, (_) => GlobalKey());

  bool _creating = false;

  /// Photographs every page and binds the pictures. Three device pixels per
  /// point — sharp on paper, and a five-page report still under a few MB.
  Future<void> _createPdf() async {
    if (_creating) return;
    setState(() => _creating = true);

    try {
      // Every page is painted on the frame after the spinner's setState —
      // the column is not lazy, so none is skipped for being off-screen.
      // Wait for that frame; a boundary photographed before it has painted
      // has nothing to give.
      await WidgetsBinding.instance.endOfFrame;

      final List<PagePicture> pictures = [];
      for (final GlobalKey key in _keys) {
        final RenderObject? object = key.currentContext?.findRenderObject();
        if (object is! RenderRepaintBoundary) {
          throw StateError('page not on screen');
        }
        final ui.Image image = await object.toImage(pixelRatio: 3);
        try {
          final ByteData? bytes =
              await image.toByteData(format: ui.ImageByteFormat.rawRgba);
          if (bytes == null) throw StateError('page could not be read');
          pictures.add(PagePicture(
              bytes.buffer.asUint8List(), image.width, image.height));
        } finally {
          image.dispose();
        }
      }

      // Read here, not in the builder: the translations live on this
      // isolate, and the builder runs on another.
      final String title = 'personal_report'.tr;
      final String author =
          _controller.userName.isEmpty ? 'app_name'.tr : _controller.userName;
      final Uint8List pdf =
          await ReportPdfBuilder.build(pictures, title: title, author: author);
      if (!mounted) return;

      Get.to(() => ReportPdfScreen(bytes: pdf, fileName: _fileName()));
    } catch (e) {
      debugPrint('Report: PDF failed — $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_create_pdf'.tr);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  String _fileName() {
    final DateFormat day = DateFormat('yyyy-MM-dd');
    return 'money-report_${day.format(widget.filter.range.start)}'
        '_${day.format(widget.filter.range.end)}.pdf';
  }

  @override
  Widget build(BuildContext context) {
    // The page is drawn at A4 points and shrunk to the screen; the scale is
    // what keeps the on-screen card in the sheet's proportions.
    final double cardWidth = MediaQuery.of(context).size.width - 32;
    final double scale = cardWidth / ReportLayout.pageWidth;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: CustomAppBar(
        title: 'report_view'.tr,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: _countPill(context)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < _pages.length; i++) ...[
              if (i > 0) const SizedBox(height: 18),
              Text(
                'page_of'.trParams({'n': '${i + 1}', 'm': '${_pages.length}'}),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppUi.muted(context),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: cardWidth,
                height: ReportLayout.pageHeight * scale,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: AppUi.softShadow(context),
                  border: Border.all(color: AppUi.hairline(context)),
                ),
                clipBehavior: Clip.antiAlias,
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: RepaintBoundary(
                    key: _keys[i],
                    child: ReportPage(
                      report: _report,
                      spec: _pages[i],
                      pageCount: _pages.length,
                      ownerName: _controller.userName,
                      ownerPhone: _controller.userPhone,
                      generatedAt: _generatedAt,
                      tagNames: _tagNames,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: CustomButton(
            text: _creating ? 'creating_pdf'.tr : 'create_pdf'.tr,
            height: 54,
            borderRadius: 14,
            isLoading: _creating,
            onPressed: _createPdf,
          ),
        ),
      ),
    );
  }

  Widget _countPill(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppUi.tint(context, primary),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${'transactions_label'.tr}: ${_report.count}   '
        '${'pages_label'.tr}: ${_pages.length}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: primary,
        ),
      ),
    );
  }
}
