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
/// which side, which categories, which tags inside each of them, which days
/// — and one button. The pages are drawn on the next screen; this one only
/// decides what goes on them, and says how many rows that is so nobody
/// generates a blank report to find out.
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

  /// The categories the report is cut to; empty is every one of them, which
  /// is where the screen opens.
  final Set<String> _picked = <String>{};

  /// Each picked category's tags, kept apart from every other category's —
  /// narrowing food to "bazar" must not narrow transport to anything, and
  /// "no tag" means a different set of rows under each parent. Empty, or
  /// missing, is all of that category's rows.
  final Map<String, Set<String>> _tags = <String, Set<String>>{};

  ReportPeriod _period = ReportPeriod.thisMonth;
  DateTimeRange? _customRange;

  DateTimeRange? _range(PersonalController c) => _period == ReportPeriod.custom
      ? _customRange
      : _period.rangeOn(DateTime.now(), earliest: c.earliestEntry);

  /// The filter as it stands, with anything that has since been deleted
  /// left out of it: a custom category or a tag removed on another screen
  /// while this one sat open is passed over rather than filtered on — the
  /// same bargain the entries sheet strikes with a tag that vanished under
  /// it.
  ReportFilter? _filter(PersonalController c) {
    final DateTimeRange? range = _range(c);
    if (range == null) return null;

    final Set<String> categories = {
      for (final PersonalCategory category in _pickerCategories)
        if (_picked.contains(category.key)) category.key,
    };

    final Map<String, Set<String>> tags = {};
    for (final String key in categories) {
      final Set<String> picked = _liveTags(c, key);
      if (picked.isNotEmpty) tags[key] = picked;
    }

    return ReportFilter(
      range: range,
      flow: _side.flow,
      categories: categories,
      tags: tags,
    );
  }

  /// One category's picked tags, minus the ones that no longer exist.
  Set<String> _liveTags(PersonalController c, String category) {
    final Set<String> picked = _tags[category] ?? const {};
    if (picked.isEmpty) return const {};

    final Set<String> alive = {
      ReportFilter.untagged,
      for (final Subcategory sub in c.subcategoriesOf(category)) sub.id,
    };
    return picked.where(alive.contains).toSet();
  }

  /// The categories on offer: one side's, or both sides' one after the
  /// other when the report is of both.
  List<PersonalCategory> get _pickerCategories => [
        if (_side != _Side.income) ...PersonalCategory.pickerFor(false),
        if (_side != _Side.expense) ...PersonalCategory.pickerFor(true),
      ];

  /// A category joins or leaves the report. Leaving takes its tags with it:
  /// a narrowing nobody can see would otherwise come back on the day the
  /// category did.
  void _toggleCategory(String key) {
    setState(() {
      if (_picked.remove(key)) {
        _tags.remove(key);
      } else {
        _picked.add(key);
      }
    });
  }

  /// A tag inside one category joins or leaves that category's pick. Down
  /// to none is "all of them" again, so the empty set is dropped rather
  /// than kept as a filter that would match nothing.
  void _toggleTag(String category, String id) {
    setState(() {
      final Set<String> picked = _tags.putIfAbsent(category, () => <String>{});
      if (!picked.remove(id)) picked.add(id);
      if (picked.isEmpty) _tags.remove(category);
    });
  }

  void _clearCategories() {
    setState(() {
      _picked.clear();
      _tags.clear();
    });
  }

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
                      // empties the picks rather than keep ones the new
                      // list does not have.
                      onChanged: (side) => setState(() {
                        _side = side ?? _Side.all;
                        _picked.clear();
                        _tags.clear();
                      }),
                    ),
                    const SizedBox(height: 16),
                    _buildCategoryPicker(context, c),
                    const SizedBox(height: 16),
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

  /// ------------------------------------------------------------- categories

  /// Categories as chips rather than a dropdown: the report may be of as
  /// many of them as the reader likes, and a list that shows every pick at
  /// once is the only honest way to say which those are. Nothing picked is
  /// every category — the same "All" the dropdown opened on, said in the
  /// line under the title instead of as a row of its own.
  ///
  /// Each picked category that has tags gets its own row of them straight
  /// underneath, so a tag is always read against the category it belongs
  /// to and can never be mistaken for another's.
  Widget _buildCategoryPicker(BuildContext context, PersonalController c) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final List<PersonalCategory> options = _pickerCategories;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.category_rounded, size: 20, color: primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'category'.tr,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppUi.body(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _picked.isEmpty
                        ? 'all_categories'.tr
                        : 'n_selected'
                            .trParams({'count': '${_picked.length}'}),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppUi.muted(context),
                    ),
                  ),
                ],
              ),
            ),
            if (_picked.isNotEmpty)
              InkWell(
                onTap: _clearCategories,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    'reset_filters'.tr,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: primary,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final PersonalCategory category in options)
              _categoryChip(context, category),
          ],
        ),
        for (final PersonalCategory category in options)
          if (_picked.contains(category.key)) _tagPicker(context, c, category),
      ],
    );
  }

  Widget _categoryChip(BuildContext context, PersonalCategory category) {
    final bool selected = _picked.contains(category.key);
    final Color accent = AppUi.accent(context, category.color);

    return GestureDetector(
      onTap: () => _toggleCategory(category.key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppUi.tint(context, category.color)
              : AppUi.neutralSurface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                selected ? accent.withOpacity(0.6) : AppUi.hairline(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected ? Icons.check_rounded : category.icon,
              size: 15,
              color: selected ? accent : AppUi.muted(context),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(
                category.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? accent : AppUi.body(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One picked category's tags, in a box of its own so the row can never
  /// be read as belonging to the category above or below it. "All" leads
  /// and is where every category starts; "Untagged" closes it, for the rows
  /// of this category that carry no tag at all.
  Widget _tagPicker(
    BuildContext context,
    PersonalController c,
    PersonalCategory category,
  ) {
    final List<Subcategory> subs = c.subcategoriesOf(category.key);
    if (subs.isEmpty) return const SizedBox.shrink();

    final Set<String> picked = _liveTags(c, category.key);
    final Color accent = AppUi.accent(context, category.color);

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: AppUi.neutralSurface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(category.icon, size: 14, color: accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  category.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ),
              Text(
                picked.isEmpty
                    ? 'filter_all'.tr
                    : 'n_selected'.trParams({'count': '${picked.length}'}),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppUi.muted(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _tagChip(
                  context,
                  category: category,
                  label: 'filter_all'.tr,
                  selected: picked.isEmpty,
                  // Tapping "All" widens back to the whole category; tapping
                  // it when it is already on is not an accident worth acting
                  // on.
                  onTap: picked.isEmpty
                      ? null
                      : () => setState(() => _tags.remove(category.key)),
                ),
                for (final Subcategory sub in subs) ...[
                  const SizedBox(width: 8),
                  _tagChip(
                    context,
                    category: category,
                    label: sub.name,
                    selected: picked.contains(sub.id),
                    onTap: () => _toggleTag(category.key, sub.id),
                  ),
                ],
                const SizedBox(width: 8),
                _tagChip(
                  context,
                  category: category,
                  label: 'untagged'.tr,
                  selected: picked.contains(ReportFilter.untagged),
                  onTap: () =>
                      _toggleTag(category.key, ReportFilter.untagged),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tagChip(
    BuildContext context, {
    required PersonalCategory category,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final Color accent = AppUi.accent(context, category.color);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppUi.tint(context, category.color)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color:
                selected ? accent.withOpacity(0.6) : AppUi.hairline(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(Icons.check_rounded, size: 13, color: accent),
              const SizedBox(width: 5),
            ],
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected ? accent : AppUi.body(context),
                ),
              ),
            ),
          ],
        ),
      ),
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
  /// for it — the period set by the calendar — has to show.
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
