import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/hiding_fab.dart';
import '../../../utils/app_ui.dart';
import '../controller/house_rules_controller.dart';
import '../model/house_rule_model.dart';
import '../widgets/house_rules_skeleton.dart';
import '../widgets/rule_editor_sheet.dart';

/// The house rules, as everyone in the house sees them.
///
/// One screen, two capabilities. Every member reads the same numbered list in
/// their own language; an admin gets the button that adds one, the menu that
/// rewords or removes one, and the handle that drags them into order. Nothing
/// is hidden from a member — a rule you cannot see is a rule you cannot keep.
class HouseRulesScreen extends StatelessWidget {
  const HouseRulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return HidingFab(
      icon: Icons.add_rounded,
      tooltip: 'add_rule'.tr,
      onPressed: () => showRuleEditorSheet(context),
      builder: (context, fab) => GetBuilder<HouseRulesController>(
        builder: (c) {
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            appBar: CustomAppBar(title: 'house_rules'.tr),
            // The button only reaches the scaffold for the people it would
            // work for; the wrapper above stays put either way so its
            // hide-on-scroll state survives a rebuild.
            floatingActionButton: c.isAdminUser ? fab : null,
            body: RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              onRefresh: c.refreshRules,
              child: _buildBody(context, c),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, HouseRulesController c) {
    if (c.isLoading) return const HouseRulesSkeleton();

    if (c.errorMessage.isNotEmpty && c.rules.isEmpty) {
      return _buildErrorState(context, c);
    }

    if (c.rules.isEmpty) return _buildEmptyState(context, c);

    return c.isAdminUser ? _buildEditableList(context, c) : _buildList(context, c);
  }

  /// ------------------------------------------------------------------ lists

  /// What a member sees: the rules, and who last changed them.
  Widget _buildList(BuildContext context, HouseRulesController c) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: c.rules.length + 2, // header, rules, footer
      separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 16 : 12),
      itemBuilder: (context, index) {
        if (index == 0) return _buildHeader(context, c);
        if (index == c.rules.length + 1) return _buildFootnote(context, c);
        return _buildRuleCard(context, c, c.rules[index - 1], index - 1);
      },
    );
  }

  /// The same list for an admin, with each row draggable by its handle.
  ///
  /// `buildDefaultDragHandles` is off because the whole card is not the grip:
  /// a long press anywhere on a rule would fight the menu button sitting in
  /// its corner.
  Widget _buildEditableList(BuildContext context, HouseRulesController c) {
    return ReorderableListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      buildDefaultDragHandles: false,
      header: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 16),
        child: _buildHeader(context, c),
      ),
      footer: Padding(
        padding: const EdgeInsets.only(top: 16),
        child: _buildFootnote(context, c),
      ),
      itemCount: c.rules.length,
      onReorderItem: c.reorder,
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.transparent,
        elevation: 6,
        borderRadius: BorderRadius.circular(18),
        shadowColor: Colors.black.withOpacity(0.3),
        child: child,
      ),
      itemBuilder: (context, index) {
        final HouseRuleModel rule = c.rules[index];
        return Padding(
          key: ValueKey<String>(rule.id),
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildRuleCard(context, c, rule, index),
        );
      },
    );
  }

  /// ----------------------------------------------------------------- pieces

  /// What the list is and how many rules it holds — plus, for a member, why
  /// there is nothing here to tap.
  Widget _buildHeader(BuildContext context, HouseRulesController c) {
    final Color primary = Theme.of(context).colorScheme.primary;

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
                child: Icon(Icons.gavel_rounded, color: primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'house_rules'.tr,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        color: AppUi.body(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'rules_count'.trParams({'count': '${c.rules.length}'}),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppUi.muted(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                c.isAdminUser
                    ? Icons.drag_indicator_rounded
                    : Icons.lock_outline_rounded,
                size: 14,
                color: AppUi.muted(context),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.isAdminUser ? 'rules_admin_hint'.tr : 'read_only_rules'.tr,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.45,
                    color: AppUi.muted(context),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRuleCard(
    BuildContext context,
    HouseRulesController c,
    HouseRuleModel rule,
    int index,
  ) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final String secondary = rule.secondaryText(c.languageCode);

    return Container(
      padding: EdgeInsets.fromLTRB(14, 14, c.isAdminUser ? 4 : 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Numbered by position, so "rule 3" means the same thing to
          // everyone reading the list.
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppUi.tint(context, primary),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.text(c.languageCode),
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: AppUi.body(context),
                  ),
                ),
                if (secondary.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  // The other language underneath: the house speaks both, so
                  // both wordings stay in front of everyone.
                  Text(
                    secondary,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppUi.muted(context),
                    ),
                  ),
                ],
                if (rule.pending) ...[
                  const SizedBox(height: 8),
                  _buildPendingChip(context),
                ],
              ],
            ),
          ),
          if (c.isAdminUser) ...[
            _buildRuleMenu(context, c, rule),
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.only(top: 4, right: 4, left: 2),
                child: Icon(Icons.drag_indicator_rounded,
                    size: 20, color: AppUi.muted(context)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRuleMenu(
    BuildContext context,
    HouseRulesController c,
    HouseRuleModel rule,
  ) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, size: 19, color: AppUi.muted(context)),
      padding: EdgeInsets.zero,
      splashRadius: 18,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) {
        if (value == 'edit') {
          showRuleEditorSheet(context, rule: rule);
        } else if (value == 'delete') {
          _confirmDelete(context, c, rule);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 19, color: AppUi.muted(context)),
              const SizedBox(width: 12),
              Text('edit_rule'.tr),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded,
                  size: 19, color: Colors.red.shade400),
              const SizedBox(width: 12),
              Text('delete_rule'.tr,
                  style: TextStyle(color: Colors.red.shade400)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPendingChip(BuildContext context) {
    final Color fg = AppUi.accent(context, Colors.orange);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppUi.tint(context, Colors.orange),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_upload_outlined, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(
            'not_synced'.tr,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFootnote(BuildContext context, HouseRulesController c) {
    final HouseRuleModel? last = c.lastTouched;
    if (last?.updatedAt == null || (last?.updatedBy.isEmpty ?? true)) {
      return const SizedBox.shrink();
    }

    return Text(
      '${'last_updated_by'.trParams({'name': last!.updatedBy})} · '
      '${DateFormat('dd MMM, yyyy').format(last.updatedAt!)}',
      style: TextStyle(fontSize: 11, color: AppUi.muted(context)),
    );
  }

  /// ------------------------------------------------------------------ states

  /// Empty means something different to each side: an admin is one tap from
  /// the starter set, a member is being told the house has not written any
  /// down yet.
  Widget _buildEmptyState(BuildContext context, HouseRulesController c) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: AppUi.tint(context, Colors.indigo),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.gavel_rounded,
                      size: 44, color: AppUi.accent(context, Colors.indigo)),
                ),
                const SizedBox(height: 22),
                Text(
                  'no_house_rules'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppUi.body(context).withOpacity(0.75),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  c.isAdminUser
                      ? 'no_house_rules_admin_hint'.tr
                      : 'no_house_rules_hint'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppUi.muted(context),
                  ),
                ),
                if (c.isAdminUser) ...[
                  const SizedBox(height: 24),
                  CustomButton(
                    text: 'add_starter_rules'.tr,
                    height: 50,
                    borderRadius: 14,
                    isLoading: c.isSeeding,
                    onPressed: c.addStarterRules,
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => showRuleEditorSheet(context),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: Text('write_your_own'.tr),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, HouseRulesController c) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: AppUi.tint(context, Colors.red),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.cloud_off_rounded,
                      size: 44, color: AppUi.accent(context, Colors.red)),
                ),
                const SizedBox(height: 22),
                Text(
                  'failed_load_rules'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppUi.body(context).withOpacity(0.75),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'check_connection'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppUi.muted(context),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: c.refreshRules,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text('retry'.tr),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    HouseRulesController c,
    HouseRuleModel rule,
  ) {
    showConfirmDialog(
      title: 'delete_rule'.tr,
      message: 'confirm_delete_rule'.tr,
      detail: rule.text(c.languageCode),
      confirmText: 'delete'.tr,
      onConfirm: () => c.deleteRule(rule),
    );
  }
}
