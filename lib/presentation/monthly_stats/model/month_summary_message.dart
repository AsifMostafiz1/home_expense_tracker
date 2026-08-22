import 'package:get/get.dart';

import '../../../utils/app_ui.dart';
import 'month_cost_summary.dart';

/// A month's figures written out as a chat message.
///
/// The end of a month is the one time everybody has to be told the same thing
/// at once, and the ledger screen is where the numbers already are. Rather
/// than asking an admin to read them out, this turns them into the message
/// they would have typed.
///
/// Names and amounts, and nothing else. Rates, collection progress and the
/// house total all live one tap away on the ledger itself — repeating them
/// here would make a wall of text out of the one line each person opens the
/// message to find. The bubble carries a way through to the rest; see
/// `ChatMessageModel.action`.
///
/// Plain text on purpose: it lands in a chat bubble, which has no formatting
/// of its own, and it should still read as sent by a person.
class MonthSummaryMessage {
  const MonthSummaryMessage._();

  /// Everyone's figures, for the group thread.
  static String forHouse(MonthCostSummary summary) {
    final List<String> lines = [_heading(summary), ''];

    for (final MemberCostSummary member in summary.members) {
      lines.add('• ${_nameOf(member)} — ${_amountOf(member)}');
    }

    return lines.join('\n');
  }

  /// One member's figure, for their own inbox. Nobody else's is in it — a
  /// list of what the rest of the house owes is not a summary, it is a leak.
  static String forMember(
    MonthCostSummary summary,
    MemberCostSummary member,
  ) {
    return [
      _heading(summary),
      '',
      '${_nameOf(member)} — ${_amountOf(member)}',
    ].join('\n');
  }

  static String _heading(MonthCostSummary summary) =>
      '📊 ${AppUi.monthLabel(summary.month)} — ${'summary'.tr}';

  static String _nameOf(MemberCostSummary member) =>
      member.name.trim().isEmpty ? 'unknown'.tr : member.name.trim();

  /// What they owe — or, when the house owes them, what is coming back. The
  /// figure never goes out negative: the sign is carried by the words.
  static String _amountOf(MemberCostSummary member) {
    final String amount = AppUi.amount(member.grandTotal.abs());
    return member.willGet ? '$amount (${'will_get'.tr})' : amount;
  }
}
