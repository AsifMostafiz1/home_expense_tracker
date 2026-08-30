import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../utils/app_enums.dart';
import '../../../utils/app_ui.dart';
import '../controller/personal_controller.dart';
import '../model/personal_category.dart';
import '../model/personal_report.dart';
import '../model/personal_transaction.dart';
import '../model/report_period.dart';
import '../model/subcategory.dart';
import 'report_view_screen.dart';

/// Asks what the report should be of, then makes it.
///
/// A form, not a dashboard: four choices in the order somebody narrows —
/// which side, which category, which tag inside it, which days — and one
/// button. The pages are drawn on the next screen; this one only decides
/// what goes on them, and says how many rows that is so nobody generates a
/// blank report to find out.
class PersonalReportScreen extends StatefulWidget {
  const PersonalReportScreen({super.key});

  @override
  State<PersonalReportScreen> createState() => _PersonalReportScreenState();
}

/// Which side the report is of. Its own enum rather than a nullable
/// [MoneyFlow]: a dropdown reads null as "nothing chosen" and would never
/// show "All" as the pick it is.
enum _Side {
  all,
  income,
  expense;

  MoneyFlow? get flow {
    switch (this) {
      case _Side.all:
        return null;
      case _Side.income:
        return MoneyFlow.income;
      case _Side.expense:
        return MoneyFlow.expense;
    }
  }
}

class _PersonalReportScreenState extends State<PersonalReportScreen> {
  _Side _side = _Side.all;
  String _category = '';
  String _subcategory = '';
  ReportPeriod _period = ReportPeriod.thisMonth;
  DateTimeRange? _customRange;

  DateTimeRange? _range(PersonalController c) => _period == ReportPeriod.custom
      ? _customRange
      : _period.rangeOn(DateTime.now(), earliest: c.earliestEntry);

  ReportFilter? _filter(PersonalController c) {
    final DateTimeRange? range = _range(c);
    if (range == null) return null;
    return ReportFilter(
      range: range,
      flow: _side.flow,
      category: _category,
      subcategory: _subcategory,
    );
  }

  /// The categories on offer: one side's, or both sides' one after the
  /// other when the report is of both.
  List<PersonalCategory> get _categories => [
        if (_side != _Side.income) ...PersonalCategory.pickerFor(false),
        if (_side != _Side.expense) ...PersonalCategory.pickerFor(true),
      ];

  Future<void> _pickCustomRange() async {
    final DateTime now = DateTime.now();
    final DateTime first = DateTime(now.year - 3);
    // Up to the end of next month: the house screen can date an entry
    // there, and a range that could not reach it would hide money that
    // counts.
    final DateTime last = DateTime(now.year, now.month + 2, 0);

    DateTimeRange? initial =
        _customRange ?? ReportPeriod.thisMonth.rangeOn(now);
    if (initial != null &&
        (initial.start.isBefore(first) || initial.end.isAfter(last))) {
      initial = null;
    }

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: last,
      initialDateRange: initial,
      helpText: 'select_period'.tr.toUpperCase(),
      saveText: 'apply'.tr,
      builder: (context, child) {
        // Keep the app's brightness — a forced light scheme over a dark
        // theme makes the calendar unreadable.
        final ThemeData theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: theme.colorScheme.primary,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null || !mounted) return;

    setState(() {
      _period = ReportPeriod.custom;
      _customRange = DateTimeRange(
        start: DateUtils.dateOnly(picked.start),
        end: DateUtils.dateOnly(picked.end),
      );
    });
  }

  void _generate(PersonalController c) {
    final ReportFilter? filter = _filter(c);
    if (filter == null) {
      _pickCustomRange();
      return;
    }

    final PersonalReport report = PersonalReport.of(filter, c.transactions,
        subcategories: c.subcategories);
    if (report.isEmpty) {
      CustomSnackbar.show(type: SnackbarType.info, message: 'report_empty'.tr);
      return;
    }

    Get.to(() => ReportViewScreen(filter: filter));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: CustomAppBar(title: 'personal_report'.tr),
      body: GetBuilder<PersonalController>(
        builder: (c) {
          final List<Subcategory> subs = c.subcategoriesOf(_category);
          final ReportFilter? filter = _filter(c);
          final int matching = filter == null
              ? 0
              : PersonalReport.of(filter, c.transactions,
                      subcategories: c.subcategories)
                  .count;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _buildIntro(context),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppUi.hairline(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _dropdown<_Side>(
                      context,
                      label: 'report_type'.tr,
                      icon: Icons.swap_vert_rounded,
                      value: _side,
                      items: [
                        _item<_Side>(_Side.all, 'report_type_all'.tr,
                            icon: Icons.all_inclusive_rounded),
                        _item<_Side>(_Side.income, 'income'.tr,
                            icon: Icons.north_east_rounded,
                            color: Colors.green),
                        _item<_Side>(_Side.expense, 'expense_word'.tr,
                            icon: Icons.south_west_rounded,
                            color: Colors.deepOrange),
                      ],
                      // The category list is the side's; a side change
                      // empties the pick rather than keep one the new list
                      // does not have.
                      onChanged: (side) => setState(() {
                        _side = side ?? _Side.all;
                        _category = '';
                        _subcategory = '';
                      }),
                    ),
                    const SizedBox(height: 14),
                    _dropdown<String>(
                      context,
                      label: 'category'.tr,
                      icon: Icons.category_rounded,
                      value: _category,
                      items: [
                        _item<String>('', 'filter_all'.tr),
                        for (final PersonalCategory category in _categories)
                          _item<String>(category.key, category.label,
                              icon: category.icon, color: category.color),
                      ],
                      onChanged: (key) => setState(() {
                        _category = key ?? '';
                        _subcategory = '';
                      }),
                    ),
                    if (subs.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _dropdown<String>(
                        context,
                        label: 'subcategory_label'.tr,
                        icon: Icons.sell_outlined,
                        value: _subcategory,
                        items: [
                          _item<String>('', 'filter_all'.tr),
                          for (final Subcategory sub in subs)
                            _item<String>(sub.id, sub.name),
                          _item<String>(ReportFilter.untagged, 'untagged'.tr),
                        ],
                        onChanged: (id) =>
                            setState(() => _subcategory = id ?? ''),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _dropdown<ReportPeriod>(
                      context,
                      label: 'period_label'.tr,
                      icon: Icons.date_range_rounded,
                      value: _period,
                      items: [
                        for (final ReportPeriod period in ReportPeriod.values)
                          _item<ReportPeriod>(period, period.labelKey.tr),
                      ],
                      onChanged: (period) {
                        if (period == ReportPeriod.custom) {
                          _pickCustomRange();
                        } else if (period != null) {
                          setState(() => _period = period);
                        }
                      },
                    ),
                    if (_period == ReportPeriod.custom) ...[
                      const SizedBox(height: 14),
                      _rangeField(context),
                    ],
                    const SizedBox(height: 16),
                    _buildMatchLine(context, filter, matching),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              CustomButton(
                text: 'generate_report'.tr,
                height: 54,
                borderRadius: 14,
                onPressed: () => _generate(c),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildIntro(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppUi.tint(context, primary),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.summarize_rounded, size: 24, color: primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'personal_report_subtitle'.tr,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppUi.muted(context),
            ),
          ),
        ),
      ],
    );
  }

  /// The custom range, as a field like the ones above it, opening the
  /// calendar on a tap.
  Widget _rangeField(BuildContext context) {
    final DateTimeRange? range = _customRange;
    final String label = range == null
        ? 'period_custom_hint'.tr
        : '${DateFormat('d MMM yyyy').format(range.start)} – '
            '${DateFormat('d MMM yyyy').format(range.end)}';

    return InkWell(
      onTap: _pickCustomRange,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _decoration(
            context, 'select_period'.tr, Icons.calendar_month_rounded),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: range == null ? AppUi.muted(context) : AppUi.body(context),
          ),
        ),
      ),
    );
  }

  /// "N entries match" — the report's size before it is made. Also the
  /// nudge, when it is zero, to loosen something.
  Widget _buildMatchLine(
      BuildContext context, ReportFilter? filter, int matching) {
    final String text = filter == null
        ? 'period_custom_hint'.tr
        : 'entries_match'.trParams({'count': '$matching'});

    return Row(
      children: [
        Icon(
          matching > 0
              ? Icons.check_circle_rounded
              : Icons.info_outline_rounded,
          size: 15,
          color: matching > 0 ? Colors.green : AppUi.muted(context),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppUi.muted(context),
            ),
          ),
        ),
      ],
    );
  }

  /// -------------------------------------------------------------- dropdowns

  InputDecoration _decoration(
      BuildContext context, String label, IconData icon) {
    final bool dark = Theme.of(context).brightness == Brightness.dark;
    final Color line = dark ? Colors.white24 : Colors.grey.shade300;

    return InputDecoration(
      labelText: label,
      prefixIcon:
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      filled: true,
      fillColor: Theme.of(context).cardColor,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }

  DropdownMenuItem<T> _item<T>(
    T value,
    String label, {
    IconData? icon,
    MaterialColor? color,
  }) {
    return DropdownMenuItem<T>(
      value: value,
      child: Builder(
        builder: (context) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 17,
                  color: color == null
                      ? AppUi.muted(context)
                      : AppUi.accent(context, color)),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: AppUi.body(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// A dropdown in the same clothes as the text fields. A plain
  /// [DropdownButton] inside the decoration rather than the form-field
  /// flavour: the form field only takes an initial value, and a pick made
  /// for it — the category emptied when the side changes — has to show.
  Widget _dropdown<T>(
    BuildContext context, {
    required String label,
    required IconData icon,
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return InputDecorator(
      decoration: _decoration(context, label, icon),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(14),
          dropdownColor: Theme.of(context).cardColor,
          icon: Icon(Icons.expand_more_rounded, color: AppUi.muted(context)),
        ),
      ),
    );
  }
}
