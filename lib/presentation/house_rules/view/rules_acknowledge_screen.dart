import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../utils/app_enums.dart';
import '../../../utils/app_ui.dart';
import '../controller/house_rules_controller.dart';
import '../model/house_rule_model.dart';

/// The rules, put in front of a member who has not agreed to them yet.
///
/// Raised over the dashboard on the way in, and it does not go away on its
/// own: agreeing is the point, so there is no close button and the system
/// back gesture is held. Rules already agreed to arrive ticked — a member who
/// owes one new rule ticks one box, not the whole list again — and the new or
/// reworded ones are the only ones left to read.
class RulesAcknowledgeScreen extends StatelessWidget {
  const RulesAcknowledgeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: GetBuilder<HouseRulesController>(
        builder: (c) {
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: SafeArea(
              child: Column(
                children: [
                  _buildHeader(context, c),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      itemCount: c.rules.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) =>
                          _buildRuleTile(context, c, c.rules[index], index),
                    ),
                  ),
                  _buildAgreeBar(context, c),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, HouseRulesController c) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final int checked = c.checkedRuleIds.length;
    final int total = c.rules.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppUi.tint(context, primary),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.gavel_rounded, color: primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'house_rules'.tr,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        color: AppUi.body(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'rules_ack_progress'
                          .trParams({'done': '$checked', 'total': '$total'}),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppUi.muted(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'rules_ack_intro'.tr,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: AppUi.muted(context),
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : checked / total,
              minHeight: 5,
              backgroundColor: AppUi.tint(context, primary),
              valueColor: AlwaysStoppedAnimation<Color>(primary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleTile(
    BuildContext context,
    HouseRulesController c,
    HouseRuleModel rule,
    int index,
  ) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final bool checked = c.isChecked(rule);
    final bool isNew = c.needsAck(rule);
    final String secondary = rule.secondaryText(c.languageCode);

    return Material(
      color: checked
          ? AppUi.tint(context, primary)
          : Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => c.toggleChecked(rule),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: checked ? primary.withOpacity(0.45) : AppUi.hairline(context),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The box is the whole point of this screen, so it leads rather
              // than trailing where a checkbox usually sits.
              Checkbox(
                value: checked,
                onChanged: (_) => c.toggleChecked(rule),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${index + 1}.',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w900,
                            color: primary,
                          ),
                        ),
                        if (isNew) ...[
                          const SizedBox(width: 8),
                          _buildNewBadge(context, c, rule),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
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
                      Text(
                        secondary,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppUi.muted(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "NEW" for a rule nobody has seen, "UPDATED" for one that was reworded
  /// after it was agreed to — the difference is whether any version of it was
  /// acknowledged before.
  Widget _buildNewBadge(
    BuildContext context,
    HouseRulesController c,
    HouseRuleModel rule,
  ) {
    final bool reworded = c.acks.containsKey(rule.id);
    final MaterialColor color = reworded ? Colors.orange : Colors.green;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppUi.tint(context, color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        (reworded ? 'updated_badge' : 'new_badge').tr.toUpperCase(),
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: AppUi.accent(context, color),
        ),
      ),
    );
  }

  Widget _buildAgreeBar(BuildContext context, HouseRulesController c) {
    final bool ready = c.allChecked;

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
            text: 'i_agree_to_rules'.tr,
            height: 52,
            borderRadius: 14,
            isLoading: c.isAcknowledging,
            color: ready
                ? null
                : Theme.of(context).colorScheme.primary.withOpacity(0.4),
            onPressed: () async {
              // Says what is missing rather than sitting there dead — a
              // disabled button explains nothing.
              if (!ready) {
                CustomSnackbar.show(
                  type: SnackbarType.info,
                  message: 'check_every_rule_first'.tr,
                );
                return;
              }

              if (await c.acceptRules()) Get.back();
            },
          ),
        ),
      ),
    );
  }
}
