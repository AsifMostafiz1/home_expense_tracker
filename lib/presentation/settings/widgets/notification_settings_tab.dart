import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../utils/app_ui.dart';
import '../controller/settings_controller.dart';

/// The reminder half of the settings screen.
///
/// Two decisions, both an admin's: whether the house gets the evening meal
/// summary at all, and at what hour. Everybody else reads the same two values
/// greyed out — being told when to expect a notification is not privileged.
class NotificationSettingsTab extends StatelessWidget {
  final SettingsController controller;

  const NotificationSettingsTab({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final SettingsController c = controller;

    return RefreshIndicator(
      onRefresh: c.refreshConfig,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _statusCard(context, c),
          const SizedBox(height: 22),
          _sectionLabel(context, 'reminder_schedule'.tr),
          const SizedBox(height: 12),
          if (!c.isAdminUser) ...[
            _readOnlyNote(context),
            const SizedBox(height: 12),
          ],
          _form(context, c),
          const SizedBox(height: 16),
          _sectionLabel(context, 'reminder_preview'.tr),
          const SizedBox(height: 12),
          _preview(context),
          if (c.isAdminUser) ...[
            const SizedBox(height: 12),
            _testButton(context, c),
          ],
          const SizedBox(height: 16),
          _footnote(context),
        ],
      ),
    );
  }

  /// ------------------------------------------------------------ status card

  /// Whether it is on, and when the next one is due — the two things somebody
  /// opens this tab to check.
  Widget _statusCard(BuildContext context, SettingsController c) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final bool on = c.reminderEnabled;
    final MaterialColor status = on ? Colors.green : Colors.grey;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppUi.tint(context, primary),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  on
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_rounded,
                  color: primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'daily_meal_reminder'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppUi.body(context),
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppUi.tint(context, status),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  (on ? 'reminder_on' : 'reminder_off').tr.toUpperCase(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    color: AppUi.accent(context, status),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _stat(context, 'reminder_time'.tr,
                  on ? formatTime(c.reminderHour, c.reminderMinute) : '—'),
              Container(
                width: 1,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: AppUi.hairline(context),
              ),
              _stat(context, 'next_reminder'.tr,
                  on ? c.untilNextReminder : 'reminder_paused'.tr),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(BuildContext context, String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.4,
              color: AppUi.body(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: AppUi.muted(context),
            ),
          ),
        ],
      ),
    );
  }

  /// -------------------------------------------------------------------- form

  Widget _form(BuildContext context, SettingsController c) {
    final bool editable = c.isAdminUser;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile.adaptive(
            contentPadding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
            value: c.reminderEnabled,
            onChanged: editable ? c.setReminderEnabled : null,
            title: Text(
              'send_daily_reminder'.tr,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppUi.body(context),
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'send_daily_reminder_hint'.tr,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: AppUi.muted(context),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: AppUi.hairline(context)),
          _timeRow(context, c, editable: editable),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    size: 14, color: AppUi.muted(context)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'reminder_hint'.tr,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.45,
                      color: AppUi.muted(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The hour itself. Greyed rather than hidden when the reminder is off, so
  /// switching it back on shows the time it will return to.
  Widget _timeRow(
    BuildContext context,
    SettingsController c, {
    required bool editable,
  }) {
    final bool active = editable && c.reminderEnabled;
    final Color primary = Theme.of(context).colorScheme.primary;

    return ListTile(
      contentPadding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      enabled: active,
      onTap: active ? () => _pickTime(context, c) : null,
      leading: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppUi.tint(context, primary),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(Icons.schedule_rounded, size: 19, color: primary),
      ),
      title: Text(
        'reminder_time'.tr,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppUi.muted(context),
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          formatTime(c.reminderHour, c.reminderMinute),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.4,
            color: active
                ? AppUi.body(context)
                : AppUi.body(context).withOpacity(0.45),
          ),
        ),
      ),
      trailing: active
          ? Icon(Icons.edit_rounded, size: 17, color: primary)
          : Icon(Icons.lock_outline_rounded,
              size: 17, color: AppUi.muted(context)),
    );
  }

  Future<void> _pickTime(BuildContext context, SettingsController c) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: c.reminderHour, minute: c.reminderMinute),
      helpText: 'reminder_time'.tr.toUpperCase(),
    );
    if (picked == null) return;
    c.setReminderTime(picked.hour, picked.minute);
  }

  /// ----------------------------------------------------------------- preview

  /// What the reminder looks like in the shade. The names and numbers here are
  /// an example — the real ones are read from that evening's meals moments
  /// before it is sent.
  Widget _preview(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppUi.hairline(context)),
        boxShadow: AppUi.softShadow(context),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppUi.tint(context, Colors.orange),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.restaurant_rounded,
                size: 17, color: AppUi.accent(context, Colors.orange)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'reminder_preview_title'.tr,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppUi.body(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'reminder_preview_body'.tr,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: AppUi.muted(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Sends tonight's reminder to this phone now.
  ///
  /// Waiting until the evening to discover the reminder does not work is a bad
  /// way to find out, and an admin setting this up wants to see the real
  /// sentence — today's names, today's numbers — not the example above it.
  Widget _testButton(BuildContext context, SettingsController c) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return OutlinedButton.icon(
      onPressed: c.isSendingTest ? null : c.sendTestReminder,
      icon: c.isSendingTest
          ? SizedBox(
              width: 15,
              height: 15,
              child: CircularProgressIndicator(strokeWidth: 2, color: primary),
            )
          : Icon(Icons.send_rounded, size: 17, color: primary),
      label: Text(
        'send_test_reminder'.tr,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: primary,
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(46),
        side: BorderSide(color: primary.withOpacity(0.4)),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  /// ------------------------------------------------------------------ pieces

  Widget _footnote(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.phone_android_rounded,
            size: 14, color: AppUi.muted(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'reminder_device_note'.tr,
            style: TextStyle(
              fontSize: 11,
              height: 1.45,
              color: AppUi.muted(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
        color: AppUi.muted(context),
      ),
    );
  }

  Widget _readOnlyNote(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppUi.tint(context, Colors.blue),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline_rounded,
              size: 15, color: AppUi.accent(context, Colors.blue)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'read_only_reminder'.tr,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
                color: AppUi.accent(context, Colors.blue),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// `6:00 PM` out of the 24-hour pair the settings are stored as.
  static String formatTime(int hour, int minute) =>
      DateFormat('h:mm a').format(DateTime(2000, 1, 1, hour, minute));
}
