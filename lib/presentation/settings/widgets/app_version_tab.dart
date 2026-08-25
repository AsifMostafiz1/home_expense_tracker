import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../common/widgets/custom_text_field.dart';
import '../../../utils/app_constant.dart';
import '../../../utils/app_ui.dart';
import '../controller/settings_controller.dart';
import '../model/app_config_model.dart';

/// The version half of the settings screen: the version every launch is
/// checked against, and the link the update screen sends people to.
///
/// Everyone can read it — being told which version you are meant to be on is
/// not privileged. Only an admin gets to type into it.
class AppVersionTab extends StatelessWidget {
  final SettingsController controller;

  const AppVersionTab({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final SettingsController c = controller;

    return RefreshIndicator(
      onRefresh: c.refreshConfig,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildVersionCard(context, c),
          const SizedBox(height: 22),
          _buildSectionLabel(context, 'version_and_link'.tr),
          const SizedBox(height: 12),
          if (!c.isAdminUser) ...[
            _buildReadOnlyNote(context),
            const SizedBox(height: 12),
          ],
          _buildForm(context, c),
          const SizedBox(height: 16),
          _buildFootnote(context, c),
        ],
      ),
    );
  }

  /// ------------------------------------------------------------ version card

  /// What this device is running against what the house is being told to run.
  /// The comparison is the whole point of the tab, so it leads.
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
    // A member reads the same two values an admin types into — the fields
    // stay, greyed, rather than becoming a second layout to keep in step.
    final bool editable = c.isAdminUser;

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
            readOnly: !editable,
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
            readOnly: !editable,
            onChanged: c.onFieldChanged,
            // Left on for everyone: checking where the link lands is reading,
            // not editing.
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
          if (editable && c.locksOutThisBuild) ...[
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

  /// Says plainly why the fields below cannot be typed into, so a member does
  /// not read the greyed form as something broken.
  Widget _buildReadOnlyNote(BuildContext context) {
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
              'read_only_settings'.tr,
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
}
