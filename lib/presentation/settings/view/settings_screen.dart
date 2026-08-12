import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/custom_text_field.dart';
import '../../../utils/app_constant.dart';
import '../../../utils/app_ui.dart';
import '../controller/settings_controller.dart';
import '../model/app_config_model.dart';
import '../widgets/settings_skeleton.dart';

/// Admin-only app settings: the version every launch is checked against, and
/// the link the update screen sends people to.
class SettingsScreen extends GetView<SettingsController> {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<SettingsController>(
      builder: (c) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: CustomAppBar(title: 'settings'.tr),
          body: Builder(
            builder: (_) {
              if (c.isLoading) return const SettingsSkeleton();

              // The tile that leads here is admin-only; this is the second
              // lock, for a session whose role was revoked while it was open.
              if (!c.isAdminUser) return _buildLockedState(context);

              if (c.errorMessage.isNotEmpty) return _buildErrorState(context, c);

              return RefreshIndicator(
                onRefresh: c.refreshConfig,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    _buildVersionCard(context, c),
                    const SizedBox(height: 22),
                    _buildSectionLabel(context, 'app_update'.tr),
                    const SizedBox(height: 12),
                    _buildForm(context, c),
                    const SizedBox(height: 16),
                    _buildFootnote(context, c),
                  ],
                ),
              );
            },
          ),
          bottomNavigationBar:
              c.isLoading || !c.isAdminUser ? null : _buildSaveBar(context, c),
        );
      },
    );
  }

  /// ------------------------------------------------------------ version card

  /// What this device is running against what the house is being told to run.
  /// The comparison is the whole point of the screen, so it leads.
  Widget _buildVersionCard(BuildContext context, SettingsController c) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final bool behind = c.updateRequired;
    final MaterialColor status = behind ? Colors.orange : Colors.green;

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
                child: Icon(Icons.system_update_rounded,
                    color: primary, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppConstant.appName,
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
                  (behind ? 'update_required' : 'up_to_date').tr.toUpperCase(),
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
              _stat(context, 'installed_version'.tr,
                  'v${c.installedVersion.toStringAsFixed(1)}'),
              Container(
                width: 1,
                height: 26,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: AppUi.hairline(context),
              ),
              _stat(
                context,
                'live_version'.tr,
                (c.config?.appVersion.isNotEmpty ?? false)
                    ? 'v${c.config!.appVersion}'
                    : '—',
              ),
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

  Widget _buildSectionLabel(BuildContext context, String label) {
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

  /// -------------------------------------------------------------------- form

  Widget _buildForm(BuildContext context, SettingsController c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomTextField(
            controller: c.versionController,
            labelText: 'latest_version'.tr,
            hintText: '1.1',
            prefixIcon: Icons.numbers_rounded,
            errorText: c.versionError,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            onChanged: c.onFieldChanged,
          ),
          const SizedBox(height: 16),
          CustomTextField(
            controller: c.linkController,
            labelText: 'download_link'.tr,
            hintText: 'https://…',
            prefixIcon: Icons.link_rounded,
            errorText: c.linkError,
            keyboardType: TextInputType.url,
            onChanged: c.onFieldChanged,
            suffixIcon: IconButton(
              tooltip: 'open_link'.tr,
              icon: const Icon(Icons.open_in_new_rounded, size: 19),
              onPressed: c.openDownloadLink,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 14, color: AppUi.muted(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'app_update_hint'.tr,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: AppUi.muted(context),
                  ),
                ),
              ),
            ],
          ),
          if (c.locksOutThisBuild) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: AppUi.tint(context, Colors.orange),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 15, color: AppUi.accent(context, Colors.orange)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'locks_out_this_build'.tr,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: AppUi.accent(context, Colors.orange),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFootnote(BuildContext context, SettingsController c) {
    final AppConfigModel? config = c.config;
    if (config == null || config.updatedBy.isEmpty) {
      return const SizedBox.shrink();
    }

    final String when = config.updatedAt == null
        ? ''
        : ' · ${DateFormat('dd MMM, yyyy').format(config.updatedAt!)}';

    return Text(
      '${'last_updated_by'.trParams({'name': config.updatedBy})}$when',
      style: TextStyle(fontSize: 11, color: AppUi.muted(context)),
    );
  }

  /// ---------------------------------------------------------------- save bar

  Widget _buildSaveBar(BuildContext context, SettingsController c) {
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
            isLoading: c.isSaving,
            onPressed: () => _save(context, c),
          ),
        ),
      ),
    );
  }

  /// Publishing a version above this build sends the admin to the update
  /// screen too, on their very next launch. Worth one question first.
  void _save(BuildContext context, SettingsController c) {
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

  Widget _buildLockedState(BuildContext context) => _centeredState(
        context,
        icon: Icons.lock_outline_rounded,
        color: Colors.orange,
        title: 'admin_only'.tr,
        hint: 'admin_only_hint'.tr,
      );

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
