import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../common/widgets/custom_snackbar.dart';
import '../../../services/connectivity_service.dart';
import '../../../utils/app_constant.dart';
import '../../../utils/app_enums.dart';
import '../model/debt_entry.dart';
import '../model/personal_category.dart';
import '../model/personal_summary.dart';
import '../model/personal_transaction.dart';
import '../repository/personal_repository.dart';

/// A member's own books: what they earned, what they spent, and what is owed
/// between them and people outside the app.
///
/// Private by construction. Every read is filtered by the signed-in phone and
/// every write carries it, so nothing here is shared with the house — no
/// member sees another's ledger, and none of it touches meals or the shared
/// expenses.
///
/// Both lists are held whole and the months, charts and balances are worked
/// out from them in memory: switching month, or looking back six of them, is
/// then a fold over a few hundred rows rather than another round trip.
class PersonalController extends GetxController implements GetxService {
  final PersonalRepository repository;

  PersonalController({required this.repository});

  bool isLoading = true;
  bool isSaving = false;
  String errorMessage = '';

  String userPhone = '';
  String userName = '';

  List<PersonalTransaction> transactions = [];
  List<DebtEntry> debts = [];

  /// The month the money tab is showing. Always the first of the month.
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  StreamSubscription<List<PersonalTransaction>>? _transactionsSub;
  StreamSubscription<List<DebtEntry>>? _debtsSub;

  bool _transactionsLoaded = false;
  bool _debtsLoaded = false;

  bool get _isOffline =>
      Get.isRegistered<ConnectivityService>() &&
      Get.find<ConnectivityService>().isOffline;

  @override
  void onInit() {
    super.onInit();
    _start();
  }

  @override
  void onClose() {
    _transactionsSub?.cancel();
    _debtsSub?.cancel();
    super.onClose();
  }

  Future<void> _start() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    userPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
    userName = prefs.getString(AppConstant.keyUserName) ?? '';

    if (userPhone.isEmpty) {
      isLoading = false;
      update();
      return;
    }

    _watch();
  }

  void _watch() {
    _transactionsSub?.cancel();
    _debtsSub?.cancel();

    _transactionsSub = repository.watchTransactions(userPhone).listen(
      (list) {
        transactions = list;
        _transactionsLoaded = true;
        _settleLoading();
      },
      onError: (Object e) {
        debugPrint('Personal: transactions stream failed — $e');
        errorMessage = e.toString();
        _transactionsLoaded = true;
        _settleLoading();
      },
    );

    _debtsSub = repository.watchDebts(userPhone).listen(
      (list) {
        debts = list;
        _debtsLoaded = true;
        _settleLoading();
      },
      onError: (Object e) {
        debugPrint('Personal: debts stream failed — $e');
        errorMessage = e.toString();
        _debtsLoaded = true;
        _settleLoading();
      },
    );
  }

  void _settleLoading() {
    if (_transactionsLoaded && _debtsLoaded) isLoading = false;
    update();
  }

  /// Pull-to-refresh: the streams already keep both lists current, so this
  /// re-attaches them, which is what recovers a listener that fell over while
  /// the connection was gone.
  Future<void> refreshAll() async {
    if (userPhone.isEmpty) return _start();
    _watch();
    if (Get.isRegistered<ConnectivityService>()) {
      unawaited(Get.find<ConnectivityService>().probe());
    }
  }

  /// ------------------------------------------------------------------ money

  void goToMonth(DateTime month) {
    selectedMonth = DateTime(month.year, month.month);
    update();
  }

  void previousMonth() =>
      goToMonth(DateTime(selectedMonth.year, selectedMonth.month - 1));

  void nextMonth() =>
      goToMonth(DateTime(selectedMonth.year, selectedMonth.month + 1));

  /// The current month is as far forward as the ledger goes — money is
  /// recorded after it moves, not before.
  ///
  /// One exception: the house expense screen records into next month as well
  /// as this one, and the copy of such an entry lands here. A month that has
  /// something in it has to be reachable, or the entry counts towards the
  /// totals while being impossible to look at.
  bool get canGoForward {
    final DateTime now = DateTime.now();
    if (selectedMonth.isBefore(DateTime(now.year, now.month))) return true;

    final String next = PersonalTransaction.monthKeyOf(
        DateTime(selectedMonth.year, selectedMonth.month + 1));
    return transactions.any((entry) => entry.monthKey == next);
  }

  List<PersonalTransaction> get monthTransactions {
    final String key = PersonalTransaction.monthKeyOf(selectedMonth);
    return transactions
        .where((entry) => entry.monthKey == key)
        .toList(growable: false);
  }

  /// This month's entries under the day each was recorded on — what the list
  /// actually shows.
  List<MoneyDay> get monthDays => MoneyDay.group(monthTransactions);

  MonthMoney get monthMoney => MonthMoney.of(selectedMonth, transactions);

  /// What the member is worth as the month on screen closes — every month
  /// before it carried forward, plus this one, plus the dues on either side.
  /// See [WalletBalance].
  WalletBalance get wallet =>
      WalletBalance.of(selectedMonth, transactions, debts: debts);

  /// The months that balance is built out of — this year one by one, and
  /// everything older as a single figure carried into it.
  WalletTimeline get walletTimeline =>
      WalletTimeline.of(selectedMonth, transactions);

  /// The people behind its dues, as they stood when that month closed — the
  /// same cut [wallet] takes, so the two agree. Squared-off accounts are left
  /// out: they add nothing, and a statement is a list of what moved it.
  List<PersonBalance> get walletPeople {
    final String key = PersonalTransaction.monthKeyOf(selectedMonth);
    return PersonBalance.group(debts.where((entry) =>
            entry.monthKey.isNotEmpty && entry.monthKey.compareTo(key) <= 0))
        .where((person) => !person.isSettled)
        .toList();
  }

  /// The last six months, oldest first — what the trend chart draws.
  List<MonthMoney> get trend {
    return [
      for (int back = 5; back >= 0; back--)
        MonthMoney.of(
          DateTime(selectedMonth.year, selectedMonth.month - back),
          transactions,
        ),
    ];
  }

  /// This month's spending per category, biggest first.
  List<CategoryTotal> categoryTotals({required bool income}) {
    final Map<String, double> totals = {};
    for (final PersonalTransaction entry in monthTransactions) {
      if (entry.isIncome != income) continue;
      final String key =
          entry.category.isEmpty ? PersonalCategory.unknown.key : entry.category;
      totals[key] = (totals[key] ?? 0) + entry.amount;
    }

    final List<CategoryTotal> list = totals.entries
        .map((entry) => CategoryTotal(entry.key, entry.value))
        .toList();
    list.sort((a, b) => b.amount.compareTo(a.amount));
    return list;
  }

  /// Everything ever recorded, for the "since you started" line.
  double get lifetimeIncome => transactions
      .where((entry) => entry.isIncome)
      .fold<double>(0, (sum, entry) => sum + entry.amount);

  double get lifetimeExpense => transactions
      .where((entry) => !entry.isIncome)
      .fold<double>(0, (sum, entry) => sum + entry.amount);

  Future<bool> saveTransaction({
    PersonalTransaction? existing,
    required MoneyFlow flow,
    required double amount,
    required String category,
    required String note,
    required DateTime date,
    required TimeOfDay time,
  }) async {
    if (userPhone.isEmpty) return false;

    try {
      isSaving = true;
      update();

      final bool offline = _isOffline;

      await repository.saveTransaction(PersonalTransaction(
        id: existing?.id ?? '',
        ownerPhone: userPhone,
        // Carried, not dropped: a copy of a house expense stays marked as one
        // whatever route reaches this. The screen keeps those out of the
        // editor, and this is what makes a way past it harmless.
        source: existing?.source ?? '',
        flow: flow,
        amount: amount,
        category: category,
        note: note.trim(),
        date: PersonalTransaction.keyOf(date),
        timeHour: time.hour,
        timeMinute: time.minute,
      ));

      // The month the entry belongs to, so a row saved for another month is
      // not written into a screen that cannot show it.
      goToMonth(date);

      CustomSnackbar.show(
        type: offline ? SnackbarType.info : SnackbarType.success,
        message: offline ? 'saved_offline_generic'.tr : 'entry_saved'.tr,
      );
      return true;
    } catch (e) {
      debugPrint('Error saving personal transaction: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_save_entry'.tr);
      return false;
    } finally {
      isSaving = false;
      update();
    }
  }

  Future<void> deleteTransaction(PersonalTransaction transaction) async {
    try {
      final bool offline = _isOffline;
      await repository.deleteTransaction(transaction.id);
      CustomSnackbar.show(
        type: offline ? SnackbarType.info : SnackbarType.success,
        message: offline ? 'saved_offline_generic'.tr : 'entry_deleted'.tr,
      );
    } catch (e) {
      debugPrint('Error deleting personal transaction: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_delete_entry'.tr);
    }
  }

  /// ------------------------------------------------------------ dena-paona

  /// One row per person, biggest outstanding first, settled accounts last.
  List<PersonBalance> get people => PersonBalance.group(debts);

  PersonBalance? personFor(String key) {
    for (final PersonBalance person in people) {
      if (person.key == key) return person;
    }
    return null;
  }

  /// What the whole ledger comes to: what is owed to the member, and what
  /// they owe. Kept apart rather than netted — one number would hide both.
  double get totalReceivable => people
      .where((person) => person.owesMe)
      .fold<double>(0, (sum, person) => sum + person.balance);

  double get totalPayable => people
      .where((person) => !person.owesMe && !person.isSettled)
      .fold<double>(0, (sum, person) => sum + person.balance.abs());

  /// Names already in the ledger — the editor offers them so a second entry
  /// for the same person does not start a second account.
  List<String> get knownPeople =>
      people.map((person) => person.name).where((name) => name.isNotEmpty).toList();

  Future<bool> saveDebtEntry({
    DebtEntry? existing,
    required String personName,
    String personPhone = '',
    required DebtFlow flow,
    required double amount,
    required String note,
    required DateTime date,
    required TimeOfDay time,
  }) async {
    if (userPhone.isEmpty) return false;

    try {
      isSaving = true;
      update();

      final bool offline = _isOffline;

      await repository.saveDebtEntry(DebtEntry(
        id: existing?.id ?? '',
        ownerPhone: userPhone,
        personName: personName.trim(),
        personPhone: personPhone.trim(),
        flow: flow,
        amount: amount,
        note: note.trim(),
        date: PersonalTransaction.keyOf(date),
        timeHour: time.hour,
        timeMinute: time.minute,
      ));

      CustomSnackbar.show(
        type: offline ? SnackbarType.info : SnackbarType.success,
        message: offline ? 'saved_offline_generic'.tr : 'entry_saved'.tr,
      );
      return true;
    } catch (e) {
      debugPrint('Error saving debt entry: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_save_entry'.tr);
      return false;
    } finally {
      isSaving = false;
      update();
    }
  }

  Future<void> deleteDebtEntry(DebtEntry entry) async {
    try {
      final bool offline = _isOffline;
      await repository.deleteDebtEntry(entry.id);
      CustomSnackbar.show(
        type: offline ? SnackbarType.info : SnackbarType.success,
        message: offline ? 'saved_offline_generic'.tr : 'entry_deleted'.tr,
      );
    } catch (e) {
      debugPrint('Error deleting debt entry: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_delete_entry'.tr);
    }
  }

  /// Clears one person's whole account — every row, not a settling entry.
  Future<void> deletePerson(PersonBalance person) async {
    try {
      await repository.deletePerson(person.entries);
      CustomSnackbar.show(
          type: SnackbarType.success, message: 'person_removed'.tr);
    } catch (e) {
      debugPrint('Error deleting person ledger: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_delete_entry'.tr);
    }
  }
}
