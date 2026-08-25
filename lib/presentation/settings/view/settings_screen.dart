import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../utils/app_ui.dart';
import '../controller/settings_controller.dart';
import '../widgets/app_version_tab.dart';
import '../widgets/notification_settings_tab.dart';
import '../widgets/settings_skeleton.dart';

/// App settings, in two tabs.
///
/// **App version** is the gate every launch passes through — the version the
/// house is told to run, and where to get it. **Notifications** is the daily
/// meal reminder: whether it goes out, and at what hour.
///
/// They share one Firestore document and one controller, but save separately:
/// an admin moving the reminder must not publish whatever half-typed version
/// number is sitting in the other tab. So the bar at the bottom belongs to
/// whichever tab is open.
///
/// Everyone can read both. Only an admin gets the form and the save bar.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  static const int _versionTab = 0;

  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    // The save bar changes with the tab, and a swipe changes the tab without
    // going through onTap.
    _tabs.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabs.indexIsChanging) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<SettingsController>(
      builder: (c) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: CustomAppBar(
            title: 'settings'.tr,
            bottom: _tabBar(context),
          ),
          body: Builder(
            builder: (_) {
              if (c.isLoading) return const SettingsSkeleton();
              if (c.errorMessage.isNotEmpty) return _buildErrorState(context, c);

              return TabBarView(
                controller: _tabs,
                children: [
                  AppVersionTab(controller: c),
                  NotificationSettingsTab(controller: c),
                ],
              );
            },
          ),
          bottomNavigationBar: _saveBar(context, c),
        );
      },
    );
  }

  PreferredSizeWidget _tabBar(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return PreferredSize(
      preferredSize: const Size.fromHeight(46),
      child: SizedBox(
        height: 46,
        child: TabBar(
          controller: _tabs,
          labelColor: primary,
          unselectedLabelColor: AppUi.muted(context),
          indicatorColor: primary,
          indicatorWeight: 2.5,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: AppUi.hairline(context),
          labelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
          unselectedLabelStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: -0.2,
          ),
          tabs: [
            Tab(text: 'app_version'.tr),
            Tab(text: 'notifications'.tr),
          ],
        ),
      ),
    );
  }

  /// ---------------------------------------------------------------- save bar

  /// Nothing to save for a member, and nothing to save before the document has
  /// been read.
  Widget? _saveBar(BuildContext context, SettingsController c) {
    if (c.isLoading || c.errorMessage.isNotEmpty || !c.isAdminUser) return null;

    final bool onVersion = _tabs.index == _versionTab;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: AppUi.hairline(context))),
        boxShadow: AppUi.softShadow(context),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: CustomButton(
            text: 'save_changes'.tr,
            height: 52,
            borderRadius: 14,
            isLoading: onVersion ? c.isSaving : c.isSavingReminder,
            onPressed: onVersion
                ? () => _saveVersion(context, c)
                : c.saveReminder,
          ),
        ),
      ),
    );
  }

  /// Publishing a version above this build sends the admin to the update
  /// screen too, on their very next launch. Worth one question first.
  void _saveVersion(BuildContext context, SettingsController c) {
    if (!c.validate()) return;

    if (!c.locksOutThisBuild) {
      c.save();
      return;
    }

    showConfirmDialog(
      title: 'force_update_title'.tr,
      message: 'confirm_force_update'.trParams({
        'version': c.versionController.text.trim(),
        'current': c.installedVersion.toStringAsFixed(1),
      }),
      detail: 'force_update_note'.tr,
      confirmText: 'save_changes'.tr,
      confirmColor: Colors.orange.shade700,
      onConfirm: c.save,
    );
  }

  /// ------------------------------------------------------------------ states

  Widget _buildErrorState(BuildContext context, SettingsController c) =>
      _centeredState(
        context,
        icon: Icons.cloud_off_rounded,
        color: Colors.red,
        title: 'failed_load_config'.tr,
        hint: 'check_connection'.tr,
        action: TextButton.icon(
          onPressed: c.load,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text('retry'.tr),
        ),
      );

  Widget _centeredState(
    BuildContext context, {
    required IconData icon,
    required MaterialColor color,
    required String title,
    required String hint,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: AppUi.tint(context, color),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: AppUi.accent(context, color)),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppUi.body(context).withOpacity(0.75),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppUi.muted(context),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              action,
            ],
          ],
        ),
      ),
    );
  }
}
