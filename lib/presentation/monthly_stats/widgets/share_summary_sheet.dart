import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/custom_snackbar.dart';
import '../../../common/widgets/profile_avatar.dart';
import '../../../utils/app_enums.dart';
import '../../../utils/app_ui.dart';
import '../../chat/controller/chat_controller.dart';
import '../../chat/controller/chat_list_controller.dart';
import '../../chat/controller/chat_sender.dart';
import '../../chat/model/chat_message_model.dart';
import '../../chat/model/chat_thread_model.dart';
import '../../chat/widgets/group_avatar.dart';
import '../model/month_cost_summary.dart';
import '../model/month_summary_message.dart';

/// Where a month's figures should go.
///
/// The group gets everybody's, because that is the conversation the whole
/// house reads. A member's inbox gets only theirs — sending one person a list
/// of what everyone else owes is not a summary, it is a leak.
void showShareSummarySheet(BuildContext context, MonthCostSummary summary) {
  Get.bottomSheet(
    _ShareSummarySheet(summary: summary),
    isScrollControlled: true,
    // The sheet paints its own rounded surface; without this the route puts a
    // square-cornered theme colour behind it.
    backgroundColor: Colors.transparent,
  );
}

class _ShareSummarySheet extends StatefulWidget {
  final MonthCostSummary summary;

  const _ShareSummarySheet({required this.summary});

  @override
  State<_ShareSummarySheet> createState() => _ShareSummarySheetState();
}

class _ShareSummarySheetState extends State<_ShareSummarySheet> {
  /// Whichever row is being sent, so only it shows work in progress.
  String? _sending;

  String get _myPhone => Get.isRegistered<ChatListController>()
      ? Get.find<ChatListController>().myPhone
      : '';

  /// Everyone with a phone to write to, minus whoever is doing the sharing —
  /// there is no conversation with yourself.
  List<MemberCostSummary> get _people => widget.summary.members
      .where((m) => m.phone.isNotEmpty && m.phone != _myPhone)
      .toList();

  Future<void> _shareToGroup() async {
    await _share(
      key: '_group',
      text: MonthSummaryMessage.forHouse(widget.summary),
      done: 'summary_sent_to_group'.tr,
    );
  }

  Future<void> _shareTo(MemberCostSummary member) async {
    await _share(
      key: member.phone,
      text: MonthSummaryMessage.forMember(widget.summary, member),
      peerPhone: member.phone,
      peerName: member.name,
      done: 'summary_sent_to'.trParams({'name': member.name}),
    );
  }

  Future<void> _share({
    required String key,
    required String text,
    required String done,
    String? peerPhone,
    String peerName = '',
  }) async {
    if (_sending != null) return;
    setState(() => _sending = key);

    final bool sent = await ChatSender.send(
      text: text,
      peerPhone: peerPhone,
      peerName: peerName,
      // What the bubble's "tap to see details" opens. The rest of the month
      // is on the ledger, not in the message.
      action: ChatMessageModel.actionMonthlySummary,
    );

    if (!mounted) return;
    setState(() => _sending = null);

    if (!sent) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_send_summary'.tr);
      return;
    }

    Get.back();
    // "Queued", not "delivered" — the outbox may be waiting for a connection,
    // and the thread itself is where the message's own state is shown.
    CustomSnackbar.show(type: SnackbarType.success, message: done);
  }

  @override
  Widget build(BuildContext context) {
    final List<MemberCostSummary> people = _people;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
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
            'send_summary_to'.tr,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            AppUi.monthLabel(widget.summary.month),
            style: TextStyle(fontSize: 12.5, color: AppUi.muted(context)),
          ),
          const SizedBox(height: 18),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                _buildGroupRow(context),
                if (people.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'send_to_personal'.tr.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: AppUi.muted(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final MemberCostSummary member in people)
                    _buildPersonRow(context, member),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupRow(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return GetBuilder<ChatController>(
      builder: (chat) {
        final List<ChatUser> members = Get.isRegistered<ChatListController>()
            ? Get.find<ChatListController>().houseMembers
            : const <ChatUser>[];

        return _row(
          context,
          leading: GroupAvatar(
            imageUrl: chat.groupInfo.imageUrl,
            members: members,
            size: 44,
            gapColor: Theme.of(context).cardColor,
          ),
          title: chat.groupInfo.displayName,
          subtitle: 'send_to_group_hint'.tr,
          highlight: true,
          busy: _sending == '_group',
          onTap: _shareToGroup,
          accent: primary,
        );
      },
    );
  }

  Widget _buildPersonRow(BuildContext context, MemberCostSummary member) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return _row(
      context,
      leading: ProfileAvatar(
        name: member.name,
        phone: member.phone,
        size: 44,
        background: primary.withOpacity(0.14),
        foreground: primary,
        fontSize: 16,
      ),
      title: member.name.trim().isEmpty ? 'unknown'.tr : member.name,
      subtitle: member.settled
          ? 'collected'.tr
          : (member.willGet
              ? '${'will_get'.tr} · ${AppUi.amount(member.grandTotal.abs())}'
              : AppUi.amount(member.grandTotal)),
      busy: _sending == member.phone,
      onTap: () => _shareTo(member),
      accent: primary,
    );
  }

  Widget _row(
    BuildContext context, {
    required Widget leading,
    required String title,
    required String subtitle,
    required bool busy,
    required VoidCallback onTap,
    required Color accent,
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: highlight
            ? AppUi.tint(context, accent)
            : AppUi.neutralSurface(context),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // Nothing else may start while one is going out — two taps would
          // queue the same summary twice.
          onTap: _sending == null ? onTap : null,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: highlight
                    ? accent.withOpacity(0.3)
                    : AppUi.hairline(context),
              ),
            ),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.bold,
                          color: AppUi.body(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: AppUi.muted(context)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (busy)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: accent),
                  )
                else
                  Icon(Icons.send_rounded, size: 18, color: accent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
