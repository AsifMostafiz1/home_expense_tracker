import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../common/widgets/custom_snackbar.dart';
import '../../../services/push_notification_service.dart';
import '../../../utils/app_constant.dart';
import '../../../utils/app_enums.dart';
import '../../../utils/app_ui.dart';
import '../../meal/model/meal_stats.dart';
import '../../meal/repository/meal_repository.dart';
import '../../member/model/member_model.dart';
import '../model/month_cost_summary.dart';
import '../model/monthly_bill_model.dart';
import '../repository/monthly_stats_repository.dart';

/// Monthly statistics: the rent, utilities, wifi and other costs for each
/// month. Everyone may read it; only an admin may change anything.
///
/// The screen keeps two kinds of state — the saved months ([bills]) and the
/// month currently being edited (everything prefixed `form`). Amounts live in
/// [TextEditingController]s while editing, so every total on the form is
/// derived from the fields rather than mirrored into a second copy that could
/// drift.
class MonthlyStatsController extends GetxController implements GetxService {
  final MonthlyStatsRepository repository;

  /// Only used for a member's own summary — an admin's screen never needs it.
  final MealRepository mealRepository;

  MonthlyStatsController({
    required this.repository,
    required this.mealRepository,
  });

  /// ------------------------------------------------------------- session

  String userName = '';
  String userPhone = '';
  bool isAdminUser = false;

  /// ---------------------------------------------------------- month list

  bool isLoading = true;
  bool isSaving = false;
  bool isDeleting = false;
  bool isMembersLoading = false;
  String errorMessage = '';
  String membersError = '';

  List<MonthlyBillModel> bills = [];
  List<MemberModel> members = [];

  /// This month worked out for whoever is looking, so a member sees what they
  /// owe instead of the whole house's accounts. Built only for members: the
  /// admin card already shows the house totals.
  MonthCostSummary? myMonthSummary;

  /// One figure per listed month: what this member owes, or paid.
  Map<String, double> myAmountByMonth = {};
  bool isMyCostLoading = false;

  MemberCostSummary? get myCost {
    final MonthCostSummary? summary = myMonthSummary;
    if (summary == null) return null;
    for (final MemberCostSummary member in summary.members) {
      if (member.phone == userPhone) return member;
    }
    return null;
  }

  /// ----------------------------------------------------------- edit form

  /// The month being edited, normalised to the first of the month.
  DateTime formMonth = DateTime(DateTime.now().year, DateTime.now().month);

  /// The saved document for [formMonth], or null while setting up a new month.
  MonthlyBillModel? editingBill;

  /// Who shares this month's bills, in display order.
  List<RentShare> formShares = [];

  final TextEditingController homeRentController = TextEditingController();
  final TextEditingController waterController = TextEditingController();
  final TextEditingController securityController = TextEditingController();
  final TextEditingController electricityController = TextEditingController();
  final TextEditingController cleaningController = TextEditingController();
  final TextEditingController wifiController = TextEditingController();
  final TextEditingController otherController = TextEditingController();
  final TextEditingController otherNoteController = TextEditingController();

  /// One amount field per member, keyed by phone number.
  final Map<String, TextEditingController> rentControllers = {};

  String? homeRentError;

  StreamSubscription<List<MemberModel>>? _membersSub;

  @override
  void onInit() {
    super.onInit();
    _watchMembers();
    // Session first and awaited: what gets loaded — and what the screen
    // offers — depends on the role, so it cannot race the data.
    _loadSession().then((_) => loadStats());
  }

  @override
  void onClose() {
    _membersSub?.cancel();
    homeRentController.dispose();
    waterController.dispose();
    securityController.dispose();
    electricityController.dispose();
    cleaningController.dispose();
    wifiController.dispose();
    otherController.dispose();
    otherNoteController.dispose();
    for (final controller in rentControllers.values) {
      controller.dispose();
    }
    rentControllers.clear();
    super.onClose();
  }

  Future<void> _loadSession() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    userName = prefs.getString(AppConstant.keyUserName) ?? '';
    userPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
    isAdminUser = prefs.getString(AppConstant.keyIsAdmin) == '1';
    update();
  }

  /// ------------------------------------------------------------- loading

  Future<void> loadStats() async {
    isLoading = true;
    errorMessage = '';
    update();

    // Fetched side by side but caught separately: a failure on one must not
    // leave the other empty, which is how the member split ends up blank with
    // nothing on screen explaining why.
    await Future.wait([_fetchBills(), refreshMembers()]);

    isLoading = false;
    update();

    if (!isAdminUser) loadMyCost();
  }

  /// Works out what the signed-in member owes — this month in full, and one
  /// figure for every other month in the list.
  ///
  /// A month they have already been collected from needs no arithmetic at all:
  /// the settlement record holds the amount that changed hands. Only the
  /// unsettled ones are computed, and the meal statistics behind them are
  /// fetched once per meal-month rather than once per row.
  Future<void> loadMyCost() async {
    if (userPhone.isEmpty) return;

    try {
      isMyCostLoading = true;
      update();

      // Bounded: the list is a house's history, not an archive to trawl.
      final List<MonthlyBillModel> targets = bills.take(12).toList();
      final Map<String, double> amounts = {};
      final Set<DateTime> mealMonths = {};

      for (final MonthlyBillModel bill in targets) {
        final SettlementRecord? settled = bill.settlements[userPhone];
        if (settled != null) {
          amounts[bill.id] = settled.amount;
          continue;
        }
        mealMonths.add(MonthCostSummary.mealMonthOf(bill.monthDate));
      }

      // The top card needs the full summary either way, settled or not.
      final MonthlyBillModel? current = currentMonthBill;
      if (current != null) {
        mealMonths.add(MonthCostSummary.mealMonthOf(current.monthDate));
      }

      final List<DateTime> months = mealMonths.toList();
      final List<MealStats> fetched = await Future.wait(
        months.map((month) => mealRepository.fetchMonthlyStats(userPhone, month)),
      );

      final Map<String, MealStats> statsByMealMonth = {
        for (int i = 0; i < months.length; i++)
          MonthlyBillModel.monthKeyOf(months[i]): fetched[i]
      };

      MonthCostSummary? summaryFor(MonthlyBillModel bill) {
        final MealStats? stats = statsByMealMonth[MonthlyBillModel.monthKeyOf(
            MonthCostSummary.mealMonthOf(bill.monthDate))];
        if (stats == null) return null;

        return MonthCostSummary.build(
          month: bill.monthDate,
          bill: bill,
          stats: stats,
          currentUserPhone: userPhone,
          currentUserName: userName,
          activeMembers: members,
        );
      }

      for (final MonthlyBillModel bill in targets) {
        if (amounts.containsKey(bill.id)) continue;
        final MonthCostSummary? summary = summaryFor(bill);
        if (summary == null) continue;
        for (final MemberCostSummary member in summary.members) {
          if (member.phone == userPhone) {
            amounts[bill.id] = member.grandTotal;
            break;
          }
        }
      }

      myAmountByMonth = amounts;
      myMonthSummary = current == null ? null : summaryFor(current);
    } catch (e) {
      debugPrint('Error loading my month costs: $e');
      myMonthSummary = null;
    } finally {
      isMyCostLoading = false;
      update();
    }
  }

  /// What this member owes for [bill], or null while it is still being worked
  /// out. Already-collected months answer from their settlement record.
  double? myAmountFor(MonthlyBillModel bill) => myAmountByMonth[bill.id];

  bool hasPaid(MonthlyBillModel bill) =>
      bill.settlements.containsKey(userPhone);

  Future<void> _fetchBills() async {
    try {
      bills = await repository.fetchMonthlyBills();
      errorMessage = '';
    } catch (e) {
      errorMessage = e.toString();
      debugPrint('Error loading monthly bills: $e');
    }
  }

  /// Keeps [members] on the house rather than on one read.
  ///
  /// The split list is the part of this screen that must never be wrong: a
  /// member who joins, leaves, or simply had not arrived yet when the screen
  /// opened shows up here without anyone reloading anything.
  void _watchMembers() {
    _membersSub?.cancel();
    isMembersLoading = members.isEmpty;

    _membersSub = repository.watchActiveMembers().listen(
      (list) {
        final bool rosterChanged = !_sameRoster(list);
        members = list;
        isMembersLoading = false;
        membersError = '';
        debugPrint('Monthly stats: ${members.length} members share the bills');

        // Only when the people changed — an unrelated field on a user document
        // must not reset amounts someone is in the middle of typing.
        if (rosterChanged) _rebuildRoster();
        update();
      },
      onError: (error) {
        isMembersLoading = false;
        membersError = error.toString();
        debugPrint('Error watching members: $error');
        update();
      },
    );
  }

  bool _sameRoster(List<MemberModel> incoming) {
    if (incoming.length != members.length) return false;
    final Set<String> current = members.map((m) => m.phone).toSet();
    return incoming.every((m) => current.contains(m.phone));
  }

  /// Re-reads the members the bills are split between, and restarts the live
  /// list if it had dropped out. Behind the retry action and every refresh.
  ///
  /// With [syncForm] the open form's roster is rebuilt around the new list,
  /// keeping every amount already typed.
  Future<void> refreshMembers({bool syncForm = false}) async {
    try {
      isMembersLoading = true;
      membersError = '';
      update();

      members = await repository.fetchActiveMembers();
      debugPrint('Monthly stats: loaded ${members.length} members for the split');

      if (syncForm) _rebuildRoster();
    } catch (e) {
      membersError = e.toString();
      debugPrint('Error loading members: $e');
    } finally {
      isMembersLoading = false;
      update();
    }

    _watchMembers();
  }

  MonthlyBillModel? billForKey(String monthKey) {
    for (final bill in bills) {
      if (bill.id == monthKey) return bill;
    }
    return null;
  }

  MonthlyBillModel? billForMonth(DateTime month) =>
      billForKey(MonthlyBillModel.monthKeyOf(month));

  DateTime get thisMonth =>
      DateTime(DateTime.now().year, DateTime.now().month);

  MonthlyBillModel? get currentMonthBill => billForMonth(thisMonth);

  bool isPastMonth(DateTime month) =>
      DateTime(month.year, month.month).isBefore(thisMonth);

  /// The months offered when adding one: the six behind us, this one, and the
  /// next — an admin sets up the month ahead, or back-fills one they missed.
  List<DateTime> get selectableMonths {
    final DateTime base = thisMonth;
    return [
      for (int offset = 1; offset >= -6; offset--)
        DateTime(base.year, base.month + offset)
    ];
  }

  /// ---------------------------------------------------------------- form

  /// The newest saved month before the one being edited — what "use previous
  /// month" copies from.
  MonthlyBillModel? get templateBill {
    final String key = MonthlyBillModel.monthKeyOf(formMonth);
    // `bills` is already newest-first, so the first earlier month wins.
    for (final bill in bills) {
      if (bill.id.compareTo(key) < 0) return bill;
    }
    return null;
  }

  /// Opens the form for [month], loading the saved bills when it has some.
  void startBill(DateTime month) {
    formMonth = DateTime(month.year, month.month);
    editingBill = billForMonth(formMonth);
    _loadForm(editingBill);

    // The split list is the whole point of the screen, so it is never left to
    // whatever the list screen happened to load: every open re-reads the
    // members, which also picks up anyone who joined since.
    refreshMembers(syncForm: true);
  }

  /// Rebuilds the roster around the current member list without losing what
  /// has already been typed into the form.
  void _rebuildRoster() {
    final Map<String, double> typed = {
      for (final share in formShares) share.phone: rentOf(share.phone)
    };

    formShares = _rosterFor(editingBill);

    _syncRentControllers({
      // What is on screen wins; a member who was not there a moment ago falls
      // back to the amount saved against them.
      for (final share in formShares)
        share.phone: typed[share.phone] ?? share.amount
    });
  }

  /// Switches the form to another month.
  ///
  /// A month that is already saved wins over whatever is on screen — the admin
  /// asked to see that month. An empty month keeps the amounts already typed,
  /// so picking the right month after starting to type costs nothing.
  void setFormMonth(DateTime month) {
    final DateTime target = DateTime(month.year, month.month);
    if (target == formMonth) return;

    final MonthlyBillModel? saved = billForMonth(target);
    formMonth = target;
    editingBill = saved;

    if (saved != null) {
      _loadForm(saved);
      return;
    }

    _rebuildRoster();
    homeRentError = null;
    update();
  }

  void _loadForm(MonthlyBillModel? bill) {
    homeRentController.text = _plain(bill?.homeRent ?? 0);
    waterController.text = _plain(bill?.waterBill ?? 0);
    securityController.text = _plain(bill?.securityBill ?? 0);
    electricityController.text = _plain(bill?.electricityBill ?? 0);
    cleaningController.text = _plain(bill?.cleaningBill ?? 0);
    wifiController.text = _plain(bill?.wifiBill ?? 0);
    otherController.text = _plain(bill?.otherCost ?? 0);
    otherNoteController.text = bill?.otherNote ?? '';

    formShares = _rosterFor(bill);
    _syncRentControllers({
      for (final share in bill?.rentShares ?? <RentShare>[])
        share.phone: share.amount
    });

    homeRentError = null;
    update();
  }

  /// Who the month is split between.
  ///
  /// A saved month keeps the roster it was saved with — recalculating an old
  /// month against today's member list would silently rewrite what people
  /// already paid. This month and the ones ahead do pick up members who joined
  /// since, which is what an admin correcting the current month expects.
  List<RentShare> _rosterFor(MonthlyBillModel? bill) {
    final List<RentShare> roster = [];
    final Set<String> seen = {};

    if (bill != null) {
      for (final share in bill.rentShares) {
        if (seen.add(share.phone)) roster.add(share);
      }
    }

    if (bill == null || !isPastMonth(formMonth)) {
      for (final member in members) {
        if (seen.add(member.phone)) {
          roster.add(RentShare(phone: member.phone, name: member.name));
        }
      }
    }

    // Names can change after a month is saved; the amounts must not.
    for (int i = 0; i < roster.length; i++) {
      final MemberModel? member = _memberFor(roster[i].phone);
      if (member != null && member.name != roster[i].name) {
        roster[i] = roster[i].copyWith(name: member.name);
      }
    }

    return roster;
  }

  MemberModel? _memberFor(String phone) {
    for (final member in members) {
      if (member.phone == phone) return member;
    }
    return null;
  }

  /// Rebuilds the per-member fields, seeding each with [amounts] and dropping
  /// the controllers of anyone no longer on the roster.
  void _syncRentControllers(Map<String, double> amounts) {
    final Set<String> roster = formShares.map((share) => share.phone).toSet();

    for (final phone in rentControllers.keys.toList()) {
      if (!roster.contains(phone)) {
        rentControllers.remove(phone)?.dispose();
      }
    }

    for (final share in formShares) {
      final TextEditingController controller = rentControllers.putIfAbsent(
        share.phone,
        () => TextEditingController(),
      );
      controller.text = _plain(amounts[share.phone] ?? 0);
    }
  }

  /// Copies the previous month's setup into the form.
  void applyTemplate() {
    final MonthlyBillModel? source = templateBill;
    if (source == null) {
      CustomSnackbar.show(
        type: SnackbarType.info,
        message: 'no_previous_month'.tr,
      );
      return;
    }

    homeRentController.text = _plain(source.homeRent);
    waterController.text = _plain(source.waterBill);
    securityController.text = _plain(source.securityBill);
    electricityController.text = _plain(source.electricityBill);
    cleaningController.text = _plain(source.cleaningBill);
    wifiController.text = _plain(source.wifiBill);
    otherController.text = _plain(source.otherCost);
    otherNoteController.text = source.otherNote;

    // Matched by phone, so a member who joined since simply starts at zero.
    _syncRentControllers({
      for (final share in source.rentShares) share.phone: share.amount
    });

    homeRentError = null;
    update();

    CustomSnackbar.show(
      type: SnackbarType.success,
      message: 'copied_from_month'
          .trParams({'month': AppUi.monthLabel(source.monthDate)}),
    );
  }

  /// Splits the rent total evenly. Worked in poisha so the parts always add
  /// back up to the total instead of losing a taka to rounding.
  void splitRentEqually() {
    if (formShares.isEmpty) return;

    final int totalPoisha = (formHomeRent * 100).round();
    final int count = formShares.length;
    final int base = totalPoisha ~/ count;
    int remainder = totalPoisha - (base * count);

    for (final share in formShares) {
      int poisha = base;
      if (remainder > 0) {
        poisha += 1;
        remainder -= 1;
      }
      rentControllers[share.phone]?.text = _plain(poisha / 100);
    }

    homeRentError = null;
    update();
  }

  /// Called from every amount field: the totals are derived, so a rebuild is
  /// all that is needed.
  void onAmountChanged([String? _]) {
    if (homeRentError != null) homeRentError = null;
    update();
  }

  /// ------------------------------------------------------------- derived

  double get formHomeRent => _parse(homeRentController.text);

  double get formUtilitiesTotal =>
      _parse(waterController.text) +
      _parse(securityController.text) +
      _parse(electricityController.text) +
      _parse(cleaningController.text);

  double get formSharedTotal =>
      formUtilitiesTotal +
      _parse(wifiController.text) +
      _parse(otherController.text);

  double get formGrandTotal => formHomeRent + formSharedTotal;

  double get formPerHeadShared =>
      formShares.isEmpty ? 0 : formSharedTotal / formShares.length;

  double rentOf(String phone) => _parse(rentControllers[phone]?.text ?? '');

  double get formAssignedRent =>
      formShares.fold(0.0, (total, share) => total + rentOf(share.phone));

  double get formRentRemaining => formHomeRent - formAssignedRent;

  bool get isRentBalanced => formRentRemaining.abs() < 0.01;

  /// What one member owes: their rent plus the equal share of everything else.
  double formTotalFor(RentShare share) =>
      rentOf(share.phone) + formPerHeadShared;

  /// --------------------------------------------------------------- write

  /// Returns true when the month was written, so the screen can close itself.
  Future<bool> saveBill() async {
    if (!isAdminUser) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'admin_only_hint'.tr);
      return false;
    }

    if (formShares.isEmpty) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'no_members_to_split'.tr);
      return false;
    }

    if (formGrandTotal <= 0) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'enter_at_least_one_bill'.tr);
      return false;
    }

    if (!isRentBalanced) {
      final double gap = formRentRemaining;
      homeRentError = (gap > 0 ? 'rent_remaining' : 'rent_over')
          .trParams({'amount': AppUi.amount(gap.abs())});
      update();
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'rent_must_match'.tr);
      return false;
    }

    try {
      isSaving = true;
      update();

      final MonthlyBillModel bill = MonthlyBillModel(
        id: MonthlyBillModel.monthKeyOf(formMonth),
        year: formMonth.year,
        month: formMonth.month,
        homeRent: formHomeRent,
        rentShares: formShares
            .map((share) => share.copyWith(amount: rentOf(share.phone)))
            .toList(),
        waterBill: _parse(waterController.text),
        securityBill: _parse(securityController.text),
        electricityBill: _parse(electricityController.text),
        cleaningBill: _parse(cleaningController.text),
        wifiBill: _parse(wifiController.text),
        otherCost: _parse(otherController.text),
        otherNote: otherNoteController.text.trim(),
        updatedBy: userName,
      );

      await repository.saveMonthlyBill(bill.id, {
        ...bill.toMap(),
        'updated_by': userName,
        'updated_by_phone': userPhone,
      });

      await loadStats();
      editingBill = billForKey(bill.id);

      // Back-filling an old month is bookkeeping; nobody needs a push for it.
      if (!isPastMonth(formMonth)) {
        await PushNotificationService().sendPushNotification(
          title: 'bill_push_title'
              .trParams({'month': AppUi.monthLabel(formMonth)}),
          body: 'bill_push_body'.trParams({
            'name': userName,
            'total': AppUi.amount(bill.grandTotal),
            'count': '${bill.memberCount}',
          }),
        );
      }

      CustomSnackbar.show(
        type: SnackbarType.success,
        message:
            'bill_saved'.trParams({'month': AppUi.monthLabel(formMonth)}),
      );
      return true;
    } catch (e) {
      debugPrint('Error saving monthly bill: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_save_bill'.tr);
      return false;
    } finally {
      isSaving = false;
      update();
    }
  }

  /// Returns true when the month was removed.
  Future<bool> deleteBill(MonthlyBillModel bill) async {
    if (!isAdminUser) return false;

    try {
      isDeleting = true;
      update();

      await repository.deleteMonthlyBill(bill.id);
      await loadStats();

      if (MonthlyBillModel.monthKeyOf(formMonth) == bill.id) {
        editingBill = null;
      }

      CustomSnackbar.show(
        type: SnackbarType.success,
        message:
            'bill_deleted'.trParams({'month': AppUi.monthLabel(bill.monthDate)}),
      );
      return true;
    } catch (e) {
      debugPrint('Error deleting monthly bill: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_delete_bill'.tr);
      return false;
    } finally {
      isDeleting = false;
      update();
    }
  }

  /// ------------------------------------------------------------- helpers

  double _parse(String value) => double.tryParse(value.trim()) ?? 0.0;

  /// Field text for an amount: whole taka lose the `.0`, and zero shows as an
  /// empty field so the hint stays visible.
  String _plain(double value) {
    if (value == 0) return '';
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }
}
