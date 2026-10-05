import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../services/task_reminder_service.dart';
import '../../../utils/app_ui.dart';
import '../controller/task_controller.dart';

/// How a task rings at its hour on this phone: ringtone, vibration, both, or
/// no alarm at all — and a test to hear the choice before trusting it.
Future<void> showTaskAlarmSettingsSheet() {
  return Get.bottomSheet(
    const _TaskAlarmSettingsSheet(),
    isScrollControlled: true,
  );
}

class _TaskAlarmSettingsSheet extends StatelessWidget {
  const _TaskAlarmSettingsSheet();

  static const List<(TaskAlarmMode, IconData, String, String)> _options = [
    (
      TaskAlarmMode.ringAndVibrate,
      Icons.vibration_rounded,
      'alarm_mode_both',
      'alarm_mode_both_hint',
    ),
    (
      TaskAlarmMode.ringOnly,
      Icons.music_note_rounded,
      'alarm_mode_ring',
      'alarm_mode_ring_hint',
    ),
    (
      TaskAlarmMode.vibrateOnly,
      Icons.smartphone_rounded,
      'alarm_mode_vibrate',
      'alarm_mode_vibrate_hint',
    ),
    (
      TaskAlarmMode.off,
      Icons.alarm_off_rounded,
      'alarm_mode_off',
      'alarm_mode_off_hint',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return GetBuilder<TaskController>(
      builder: (c) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppUi.muted(context).withOpacity(0.35),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Text(
                  'task_alarm'.tr,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(
                  'task_alarm_hint'.tr,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: AppUi.muted(context),
                  ),
                ),
                const SizedBox(height: 16),
                for (final (mode, icon, label, hint) in _options)
                  _option(context, c, mode, icon, label.tr, hint.tr),
                if (c.alarmMode != TaskAlarmMode.off) ...[
                  if (!c.exactAlarmsAllowed)
                    _warning(
                      context,
                      'alarm_exact_warning'.tr,
                      'allow_exact_alarms'.tr,
                      c.requestExactAlarms,
                    ),
                  if (!c.fullScreenAllowed)
                    _warning(
                      context,
                      'alarm_full_screen_warning'.tr,
                      'allow'.tr,
                      c.requestFullScreen,
                    ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: c.isSendingTestAlarm ? null : c.sendTestAlarm,
                    icon: c.isSendingTestAlarm
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.alarm_rounded),
                    label: Text('test_alarm'.tr),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'alarm_battery_note'.tr,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: AppUi.muted(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _option(
    BuildContext context,
    TaskController c,
    TaskAlarmMode mode,
    IconData icon,
    String label,
    String hint,
  ) {
    final bool selected = c.alarmMode == mode;
    final Color primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? primary.withOpacity(0.08) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected ? primary : AppUi.hairline(context),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => c.setAlarmMode(mode),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: [
                Icon(icon,
                    size: 22, color: selected ? primary : AppUi.muted(context)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: AppUi.body(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hint,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          color: AppUi.muted(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: selected ? primary : AppUi.muted(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _warning(
    BuildContext context,
    String text,
    String action,
    VoidCallback onPressed,
  ) {
    final Color fg = AppUi.accent(context, Colors.orange);
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
      decoration: BoxDecoration(
        color: AppUi.tint(context, Colors.orange),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
          ),
          TextButton(
            onPressed: onPressed,
            style: TextButton.styleFrom(
              foregroundColor: fg,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 34),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(action,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
