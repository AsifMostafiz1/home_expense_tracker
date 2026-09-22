import '../../expense/model/expense_model.dart';
import '../../meal/model/meal_stats.dart';
import '../../member/model/member_model.dart';
import 'monthly_bill_model.dart';

/// What one member owes for a month.
///
/// Two halves, from two different months: this month's house bills, and last
/// month's meals — the house eats first and settles a month later.
class MemberCostSummary {
  final String phone;
  final String name;
  final bool isMe;

  /// False for someone who ate last month but is not on this month's bill —
  /// they still owe for the meals, so they are listed rather than dropped.
  final bool inBills;

  final double rent;
  final double sharedBills;

  final int mealCount;
  final double mealCost;
  final double otherCost;

  /// What they already paid during the meal month — the bazar and other
  /// spending they covered for the house. It comes off the bill.
  final double mealPaid;
  final double otherPaid;

  /// The entries behind [otherPaid], gathered by item, largest first.
  final List<OtherCostItem> otherPaidItems;

  /// Set once the admin has collected this member's share.
  final bool settled;

  /// What was actually handed over, stamped at collection time — a later edit
  /// to the bills does not rewrite it.
  final double settledAmount;
  final String settledBy;
  final DateTime? settledAt;

  const MemberCostSummary({
    required this.phone,
    required this.name,
    required this.isMe,
    required this.inBills,
    required this.rent,
    required this.sharedBills,
    required this.mealCount,
    required this.mealCost,
    required this.otherCost,
    required this.mealPaid,
    required this.otherPaid,
    this.otherPaidItems = const [],
    this.settled = false,
    this.settledAmount = 0,
    this.settledBy = '',
    this.settledAt,
  });

  /// Rent plus their share of utilities, wifi and the other house costs.
  double get houseBills => rent + sharedBills;

  double get mealTotal => mealCost + otherCost;

  /// Everything charged, before anything they paid is taken off.
  double get subtotal => houseBills + mealTotal;

  double get paid => mealPaid + otherPaid;

  /// What is actually owed. Negative means the house owes them.
  double get grandTotal => subtotal - paid;

  bool get willGet => grandTotal < 0;
}

/// Every member's costs for one month, worked out in one place.
///
/// The meal figures are reproduced exactly as the meal screen computes them —
/// one house-wide meal rate, and a flat per-head share of the `others`
/// spending — because two screens disagreeing about the same month reads as a
/// bug, not as a second opinion.
class MonthCostSummary {
  /// The month the house bills belong to.
  final DateTime month;

  /// The month the meals belong to — always the one before [month].
  final DateTime mealMonth;

  final MonthlyBillModel? bill;

  final double mealRate;
  final double otherRate;
  final int totalMeals;

  final List<MemberCostSummary> members;

  /// What went into the flat "other" share — the house's non-meal spending
  /// for the meal month, before it was divided per head.
  final OtherCostBreakdown otherBreakdown;

  const MonthCostSummary({
    required this.month,
    required this.mealMonth,
    required this.bill,
    required this.mealRate,
    required this.otherRate,
    required this.totalMeals,
    required this.members,
    this.otherBreakdown = const OtherCostBreakdown(),
  });

  double get billsTotal =>
      members.fold(0.0, (sum, member) => sum + member.houseBills);

  double get mealsTotal =>
      members.fold(0.0, (sum, member) => sum + member.mealTotal);

  double get subtotal =>
      members.fold(0.0, (sum, member) => sum + member.subtotal);

  double get paidTotal => members.fold(0.0, (sum, member) => sum + member.paid);

  /// What the house still has to collect once everyone's own spending is
  /// taken off.
  double get grandTotal =>
      members.fold(0.0, (sum, member) => sum + member.grandTotal);

  /// Collection progress — the amounts as they were stamped, not as they
  /// stand today, so the tally matches the money that changed hands.
  double get collectedTotal => members
      .where((member) => member.settled)
      .fold(0.0, (sum, member) => sum + member.settledAmount);

  int get settledCount => members.where((member) => member.settled).length;

  int get pendingCount => members.length - settledCount;

  bool get isFullySettled => members.isNotEmpty && pendingCount == 0;

  bool get hasMealData => totalMeals > 0 || mealRate > 0 || otherRate > 0;

  static DateTime mealMonthOf(DateTime month) =>
      DateTime(month.year, month.month - 1);

  factory MonthCostSummary.build({
    required DateTime month,
    required MonthlyBillModel? bill,
    required MealStats stats,
    required String currentUserPhone,
    required String currentUserName,
    required List<MemberModel> activeMembers,
  }) {
    // Same two rates the meal screen shows in its total card.
    final double mealRate =
        stats.totalCount == 0 ? 0 : stats.totalExpense / stats.totalCount;
    final double otherRate =
        stats.userCount == 0 ? 0 : stats.totalOtherExpense / stats.userCount;

    final Map<String, _MealFigures> mealsByPhone = {};
    for (final Map<String, dynamic> entry in stats.otherUsersMeals) {
      final String phone = (entry['phone'] ?? '').toString();
      if (phone.isEmpty) continue;
      mealsByPhone[phone] = _MealFigures(
        name: (entry['name'] ?? '').toString(),
        count: (entry['count'] as num?)?.toInt() ?? 0,
        mealPaid: (entry['expense'] as num?)?.toDouble() ?? 0,
        otherPaid: (entry['other_expense'] as num?)?.toDouble() ?? 0,
        otherItems: OtherCostItem.group(
            ((entry['expenses'] as List?) ?? const [])
                .whereType<ExpenseModel>()),
      );
    }
    // The stats keep the viewer out of `otherUsersMeals` and hand their
    // figures back as scalars, so their row has to be put back by hand.
    if (currentUserPhone.isNotEmpty) {
      mealsByPhone[currentUserPhone] = _MealFigures(
        name: currentUserName,
        count: stats.myCount,
        mealPaid: stats.myExpense,
        otherPaid: stats.myOtherExpense,
        otherItems:
            OtherCostItem.group(stats.myExpenses.whereType<ExpenseModel>()),
      );
    }

    String nameFor(String phone, String fallback) {
      for (final MemberModel member in activeMembers) {
        if (member.phone == phone) return member.name;
      }
      if (fallback.isNotEmpty) return fallback;
      return mealsByPhone[phone]?.name ?? '';
    }

    final List<MemberCostSummary> rows = [];
    final Set<String> seen = {};

    MemberCostSummary rowFor({
      required String phone,
      required String name,
      required double rent,
      required double sharedBills,
      required bool inBills,
    }) {
      final _MealFigures? meals = mealsByPhone[phone];
      final int count = meals?.count ?? 0;
      final SettlementRecord? settlement = bill?.settlements[phone];

      return MemberCostSummary(
        phone: phone,
        name: name,
        isMe: phone == currentUserPhone,
        inBills: inBills,
        rent: rent,
        sharedBills: sharedBills,
        mealCount: count,
        mealCost: count * mealRate,
        // Flat per head, exactly as the meal screen charges it.
        otherCost: otherRate,
        mealPaid: meals?.mealPaid ?? 0,
        otherPaid: meals?.otherPaid ?? 0,
        otherPaidItems: meals?.otherItems ?? const [],
        settled: settlement != null,
        settledAmount: settlement?.amount ?? 0,
        settledBy: settlement?.by ?? '',
        settledAt: settlement?.at,
      );
    }

    // 1. The month's own roster, in the order it was saved.
    if (bill != null) {
      for (final RentShare share in bill.rentShares) {
        if (!seen.add(share.phone)) continue;
        rows.add(rowFor(
          phone: share.phone,
          name: nameFor(share.phone, share.name),
          rent: share.amount,
          sharedBills: bill.perHeadShared,
          inBills: true,
        ));
      }
    }

    // 2. Anyone who ate last month but is not on this month's bill. They owe
    //    for those meals, and leaving them out would stop the totals adding up.
    final List<MapEntry<String, _MealFigures>> extras = mealsByPhone.entries
        .where((entry) =>
            !seen.contains(entry.key) &&
            (entry.value.count > 0 ||
                entry.value.mealPaid > 0 ||
                entry.value.otherPaid > 0))
        .toList();
    extras.sort((a, b) => a.value.name.toLowerCase().compareTo(
          b.value.name.toLowerCase(),
        ));

    for (final MapEntry<String, _MealFigures> entry in extras) {
      if (!seen.add(entry.key)) continue;
      rows.add(rowFor(
        phone: entry.key,
        name: nameFor(entry.key, entry.value.name),
        rent: 0,
        sharedBills: 0,
        inBills: false,
      ));
    }

    // 3. No bill for the month at all — fall back to the house as it stands,
    //    so the meal side can still be read.
    if (bill == null) {
      for (final MemberModel member in activeMembers) {
        if (!seen.add(member.phone)) continue;
        rows.add(rowFor(
          phone: member.phone,
          name: member.name,
          rent: 0,
          sharedBills: 0,
          inBills: false,
        ));
      }
    }

    return MonthCostSummary(
      month: DateTime(month.year, month.month),
      mealMonth: mealMonthOf(month),
      bill: bill,
      mealRate: mealRate,
      otherRate: otherRate,
      totalMeals: stats.totalCount,
      members: rows,
      otherBreakdown: OtherCostBreakdown.fromStats(stats),
    );
  }
}

/// The house's "other" spending for one meal month, gathered by item so the
/// flat per-head charge can say what it paid for.
class OtherCostBreakdown {
  final double total;

  /// The heads the total was divided between — the same count the rate uses.
  final int headCount;

  /// One line per item name, largest first. Entries typed with the same name
  /// in any case are one item.
  final List<OtherCostItem> items;

  const OtherCostBreakdown({
    this.total = 0,
    this.headCount = 0,
    this.items = const [],
  });

  bool get isEmpty => items.isEmpty;

  factory OtherCostBreakdown.fromStats(MealStats stats) {
    // The viewer's entries come back on their own; everyone else's ride on
    // their row in `otherUsersMeals`.
    final List<ExpenseModel> entries = [
      ...stats.myExpenses.whereType<ExpenseModel>(),
      for (final Map<String, dynamic> row in stats.otherUsersMeals)
        ...((row['expenses'] as List?) ?? const []).whereType<ExpenseModel>(),
    ];

    return OtherCostBreakdown(
      total: stats.totalOtherExpense,
      headCount: stats.userCount,
      items: OtherCostItem.group(entries),
    );
  }
}

class OtherCostItem {
  /// As it was typed — empty for an entry saved without a description.
  final String name;
  final double amount;

  const OtherCostItem({required this.name, required this.amount});

  /// The "other" entries among [entries], one line per item name — the same
  /// name in any case is one item — largest first. Meal bazar is left out.
  static List<OtherCostItem> group(Iterable<ExpenseModel> entries) {
    final Map<String, OtherCostItem> byName = {};
    for (final ExpenseModel entry in entries) {
      if (entry.type == 'expense') continue;
      final String name = entry.description.trim();
      final String key = name.toLowerCase();
      final OtherCostItem? seen = byName[key];
      byName[key] = OtherCostItem(
        name: seen?.name ?? name,
        amount: (seen?.amount ?? 0) + entry.amount,
      );
    }
    return byName.values.toList()..sort((a, b) => b.amount.compareTo(a.amount));
  }
}

class _MealFigures {
  final String name;
  final int count;
  final double mealPaid;
  final double otherPaid;
  final List<OtherCostItem> otherItems;

  const _MealFigures({
    required this.name,
    required this.count,
    required this.mealPaid,
    required this.otherPaid,
    this.otherItems = const [],
  });
}
