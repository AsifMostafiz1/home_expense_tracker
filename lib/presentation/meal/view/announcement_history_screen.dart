import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../common/widgets/profile_avatar.dart';
import '../../../utils/app_enums.dart';
import '../controller/meal_controller.dart';

/// Palette used to give every announcer a stable, recognisable accent color.
const List<MaterialColor> _authorColors = [
  Colors.amber,
  Colors.teal,
  Colors.indigo,
  Colors.pink,
  Colors.orange,
  Colors.purple,
];

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _tint(BuildContext context, Color color) =>
    color.withOpacity(_isDark(context) ? 0.20 : 0.10);

Color _accentOn(BuildContext context, MaterialColor color) =>
    _isDark(context) ? color.shade300 : color.shade700;

Color _bodyColor(BuildContext context) =>
    Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87;

Color _mutedColor(BuildContext context) =>
    (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey)
        .withOpacity(0.65);

Color _hairline(BuildContext context) =>
    Theme.of(context).dividerColor.withOpacity(_isDark(context) ? 0.8 : 1);

MaterialColor _colorForAuthor(String name) =>
    _authorColors[name.hashCode.abs() % _authorColors.length];

/// A group of announcements that share the same calendar day.
class _DayGroup {
  final String label;
  final List<Map<String, dynamic>> items;

  _DayGroup(this.label, this.items);
}

class AnnouncementHistoryScreen extends GetView<MealController> {
  const AnnouncementHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: CustomAppBar(
        title: 'announcement_history'.tr,
        showBackButton: true,
      ),
      body: GetBuilder<MealController>(
        builder: (controller) {
          return RefreshIndicator(
            color: Theme.of(context).colorScheme.primary,
            onRefresh: () => controller.fetchAnnouncement(),
            child: controller.announcements.isEmpty
                ? _buildEmptyState(context)
                : _buildTimeline(context, _groupByDay(controller.announcements)),
          );
        },
      ),
    );
  }

  /// Groups announcements by calendar day, preserving the newest-first order
  /// they arrive in from the repository.
  List<_DayGroup> _groupByDay(List<Map<String, dynamic>> announcements) {
    final List<_DayGroup> groups = [];
    final Map<String, _DayGroup> index = {};

    for (final item in announcements) {
      final date = _dateOf(item);
      final String key = date != null
          ? DateFormat('yyyy-MM-dd').format(date)
          : 'unknown_date';

      var group = index[key];
      if (group == null) {
        group = _DayGroup(_dayLabel(date), []);
        index[key] = group;
        groups.add(group);
      }
      group.items.add(item);
    }
    return groups;
  }

  static DateTime? _dateOf(Map<String, dynamic> item) {
    final updatedAt = item['updatedAt'];
    if (updatedAt is Timestamp) return updatedAt.toDate();
    if (updatedAt is String) return DateTime.tryParse(updatedAt);
    return null;
  }

  static String _dayLabel(DateTime? date) {
    if (date == null) return 'unknown_date'.tr;
    final now = DateTime.now();
    final day = DateTime(date.year, date.month, date.day);
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'today'.tr;
    if (diff == 1) return 'yesterday'.tr;
    return DateFormat('dd MMMM, yyyy').format(date);
  }

  Widget _buildEmptyState(BuildContext context) {
    // Wrapped in a scroll view so pull-to-refresh still works when empty.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: _tint(context, Colors.amber),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.campaign_outlined,
                    size: 56, color: _accentOn(context, Colors.amber)),
              ),
              const SizedBox(height: 24),
              Text(
                'no_announcements_found'.tr,
                style: TextStyle(
                  color: _bodyColor(context).withOpacity(0.7),
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Text(
                  'announcement_empty_hint'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _mutedColor(context),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimeline(BuildContext context, List<_DayGroup> groups) {
    // Flatten day headers and announcements into a single lazily built list.
    final List<Object> rows = [];
    for (final group in groups) {
      rows.add(group.label);
      rows.addAll(group.items);
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];

        if (row is String) {
          return _buildDayHeader(context, row);
        }

        final announcement = row as Map<String, dynamic>;
        final bool isNewest = index == 1; // first row is always a day header
        final bool isLastOfDay =
            index == rows.length - 1 || rows[index + 1] is String;

        return _buildAnnouncementTile(
          context,
          announcement,
          isNewest: isNewest,
          isLastOfDay: isLastOfDay,
        );
      },
    );
  }

  Widget _buildDayHeader(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _isDark(context)
                  ? Colors.white.withOpacity(0.06)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _hairline(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_rounded,
                    size: 12, color: _mutedColor(context)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _bodyColor(context).withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: _hairline(context), height: 1)),
        ],
      ),
    );
  }

  Widget _buildAnnouncementTile(
    BuildContext context,
    Map<String, dynamic> announcement, {
    required bool isNewest,
    required bool isLastOfDay,
  }) {
    final String text = announcement['text'] ?? '';
    final String userName = announcement['user_name'] ?? 'unknown'.tr;
    final DateTime? date = _dateOf(announcement);
    final MaterialColor color = _colorForAuthor(userName);
    final String? id = announcement['id'] as String?;
    final bool isResolved = announcement['resolved'] == true;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline rail: author avatar + connector to the next item.
          Column(
            children: [
              ProfileAvatar(
                // Announcements store the author's name, not their phone, so
                // the directory falls back to a name match here.
                name: userName,
                phone: announcement['user_phone']?.toString(),
                size: 40,
                background: _tint(context, color),
                foreground: _accentOn(context, color),
                borderColor: color.withOpacity(0.45),
                fontSize: 14,
              ),
              if (!isLastOfDay)
                Expanded(
                  child: Container(
                    width: 2,
                    color: _hairline(context),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLastOfDay ? 4 : 16),
              child: Material(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: text));
                    CustomSnackbar.show(
                      type: SnackbarType.success,
                      message: 'copied'.tr,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isNewest
                            ? color.withOpacity(0.45)
                            : _hairline(context),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withOpacity(_isDark(context) ? 0.25 : 0.04),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                userName,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _accentOn(context, color),
                                  fontWeight: FontWeight.w900,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isNewest) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _tint(context, color),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'latest'.tr.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 0.6,
                                    color: _accentOn(context, color),
                                  ),
                                ),
                              ),
                            ],
                            if (isResolved) ...[
                              const SizedBox(width: 8),
                              _resolvedChip(context),
                            ],
                            const Spacer(),
                            if (date != null)
                              Text(
                                DateFormat('hh:mm a').format(date),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _mutedColor(context),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            if (id != null) ...[
                              const SizedBox(width: 4),
                              // Any member may remove any announcement.
                              Material(
                                color: Colors.transparent,
                                shape: const CircleBorder(),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  onTap: () =>
                                      _confirmDelete(context, id, text),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.delete_outline_rounded,
                                      size: 18,
                                      color: _mutedColor(context),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          text,
                          style: TextStyle(
                            fontSize: 15,
                            color: _bodyColor(context),
                            fontWeight: FontWeight.w500,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resolvedChip(BuildContext context) {
    const MaterialColor green = Colors.green;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _tint(context, green),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded,
              size: 10, color: _accentOn(context, green)),
          const SizedBox(width: 4),
          Text(
            'resolved'.tr.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
              color: _accentOn(context, green),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, String id, String text) {
    showConfirmDialog(
      title: 'delete_announcement'.tr,
      message: 'confirm_delete_announcement'.tr,
      detail: text,
      confirmText: 'delete'.tr,
      onConfirm: () => controller.deleteAnnouncement(id),
    );
  }
}
