import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../common/widgets/custom_snackbar.dart';
import '../../../services/connectivity_service.dart';
import '../../../utils/app_constant.dart';
import '../../../utils/app_enums.dart';
import '../model/custom_category.dart';
import '../model/debt_entry.dart';
import '../model/default_subcategories.dart';
import '../model/ledger_person.dart';
import '../model/personal_category.dart';
import '../model/personal_summary.dart';
import '../model/personal_transaction.dart';
import '../model/subcategory.dart';
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

  /// The people accounts are kept with, whether or not anything has passed
  /// through them yet — see [LedgerPerson].
  List<LedgerPerson> savedPeople = [];

  /// The member's own categories, fed into [PersonalCategory.register] on
  /// every snapshot so a custom key resolves wherever a fixed one does.
  List<CustomCategory> customCategories = [];

  /// How they arranged the picker, fed into
  /// [PersonalCategory.registerOrder] the same way.
  CategoryOrder categoryOrder = const CategoryOrder();

  /// The finer cuts inside their categories, all parents together — the
  /// sheet takes its slice through [subcategoriesOf].
  List<Subcategory> subcategories = [];

  /// The month the money tab is showing. Always the first of the month.
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  /// How many months past the running one the ledger opens onto.
  ///
  /// Money is usually recorded after it moves, but not always: rent paid
  /// early, a bill dated to the month it covers, and the house expense
  /// screen's own copies all land ahead of today. Three months is as far as
  /// anybody plans, so it is as far as the month switcher walks and as far
  /// as an entry may be dated.
  static const int monthsAhead = 3;

  /// The furthest month the switcher reaches, as its 1st.
  static DateTime get horizonMonth {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month + monthsAhead);
  }

  /// The last day an entry may be dated to — the end of [horizonMonth].
  static DateTime get horizonDay {
    final DateTime now = DateTime.now();
    return DateTime(now.year, now.month + monthsAhead + 1, 0);
  }

  StreamSubscription<List<PersonalTransaction>>? _transactionsSub;
  StreamSubscription<List<DebtEntry>>? _debtsSub;
  StreamSubscription<List<LedgerPerson>>? _peopleSub;
  StreamSubscription<List<CustomCategory>>? _categoriesSub;
  StreamSubscription<CategoryOrder>? _orderSub;
  StreamSubscription<List<Subcategory>>? _subcategoriesSub;

  bool _transactionsLoaded = false;
  bool _debtsLoaded = false;
  bool _peopleLoaded = false;
  bool _categoriesLoaded = false;

  // What the seeding decision waits for — see [_maybeSeedDefaults].
  bool _orderSeen = false;
  bool _subsSeen = false;
  bool _seedStarted = false;

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
    _peopleSub?.cancel();
    _categoriesSub?.cancel();
    _orderSub?.cancel();
    _subcategoriesSub?.cancel();
    // The registry is static and this sign-in's — logout deletes this
    // controller, and the next account must not read this one's categories
    // while their own snapshot is still on its way.
    PersonalCategory.clearRegistry();
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
    _peopleSub?.cancel();
    _categoriesSub?.cancel();
    _orderSub?.cancel();
    _subcategoriesSub?.cancel();

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

    _peopleSub = repository.watchPeople(userPhone).listen(
      (list) {
        savedPeople = list;
        _peopleLoaded = true;
        _settleLoading();
      },
      onError: (Object e) {
        debugPrint('Personal: people stream failed — $e');
        // Not held against the screen: the dues list is still readable from
        // the entries alone, and only the accounts with nothing in them yet
        // are missing from it.
        _peopleLoaded = true;
        _settleLoading();
      },
    );

    _categoriesSub = repository.watchCategories(userPhone).listen(
      (list) {
        customCategories = list;
        PersonalCategory.register(list);
        _categoriesLoaded = true;
        _settleLoading();
      },
      onError: (Object e) {
        debugPrint('Personal: categories stream failed — $e');
        // Also not held against the screen: without them the fixed list
        // still works, and an entry under a custom key shows as
        // uncategorised until the stream recovers.
        _categoriesLoaded = true;
        _settleLoading();
      },
    );

    _orderSub = repository.watchCategoryOrder(userPhone).listen(
      (order) {
        categoryOrder = order;
        PersonalCategory.registerOrder(order);
        _orderSeen = true;
        _maybeSeedDefaults();
        update();
      },
      onError: (Object e) {
        // Never held against the screen: the default order is a perfectly
        // good one, so this stream does not even take part in the loading
        // gate.
        debugPrint('Personal: category order stream failed — $e');
      },
    );

    _subcategoriesSub = repository.watchSubcategories(userPhone).listen(
      (list) {
        subcategories = list;
        _subsSeen = true;
        _maybeSeedDefaults();
        update();
      },
      onError: (Object e) {
        // Like the order: a picker with no subcategory row is still a
        // whole picker, so no loading gate here either.
        debugPrint('Personal: subcategories stream failed — $e');
      },
    );
  }

  /// Deals a fresh account its starter subcategories, once — see
  /// [DefaultSubcategories]. Not a blocking step anywhere: the picker works
  /// before, during and without it.
  ///
  /// It waits for both streams and for an order snapshot the SERVER has
  /// confirmed. A fresh install with no cache also reads as "never seeded",
  /// and acting on that would deal a second hand to an account that was
  /// seeded and then pruned on another device. An account that made its own
  /// subcategories before this shipped keeps them exactly as they are — the
  /// mark is set and nothing is added beside them.
  void _maybeSeedDefaults() {
    if (_seedStarted || !_orderSeen || !_subsSeen) return;
    if (categoryOrder.subsSeeded || categoryOrder.fromCache) return;
    if (userPhone.isEmpty) return;

    _seedStarted = true;
    final List<Subcategory> seeds = subcategories.isNotEmpty
        ? const []
        : DefaultSubcategories.forOwner(userPhone);

    unawaited(
      repository.seedSubcategories(userPhone, seeds).catchError(
            (Object e) =>
                debugPrint('Personal: seeding subcategories failed — $e'),
          ),
    );
  }

  void _settleLoading() {
    if (_transactionsLoaded &&
        _debtsLoaded &&
        _peopleLoaded &&
        _categoriesLoaded) {
      isLoading = false;
    }
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

  /// Points the ledger at the month that is actually running.
  ///
  /// The controller outlives the screen: it is registered for the whole
  /// session, so its two listeners are not torn down every time the tab is
  /// left. Which means a month somebody walked back to would still be up the
  /// next time they opened the ledger — and opening it means "now", not
  /// wherever it was last put down.
  ///
  /// Deliberately silent. The caller is a screen in `initState`, about to
  /// build and read this anyway; asking for a rebuild from inside a build is
  /// what throws, and nothing else on screen reads the month.
  void resetToCurrentMonth() {
    final DateTime now = DateTime.now();
    selectedMonth = DateTime(now.year, now.month);
  }

  void previousMonth() =>
      goToMonth(DateTime(selectedMonth.year, selectedMonth.month - 1));

  void nextMonth() =>
      goToMonth(DateTime(selectedMonth.year, selectedMonth.month + 1));

  /// [monthsAhead] months past the running one is as far forward as the
  /// ledger goes — far enough to put next quarter's rent in, not so far that
  /// the switcher walks into empty years.
  ///
  /// One exception past that: an entry can be dated further out than the
  /// window reaches — the house expense screen's copies, or one saved back
  /// when the window sat elsewhere. A month that has something in it has to
  /// be reachable, or the entry counts towards the totals while being
  /// impossible to look at.
  bool get canGoForward {
    if (selectedMonth.isBefore(horizonMonth)) return true;

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
  /// actually shows. [flow] narrows it to one side, null is both; [range]
  /// narrows it to a run of days inside the month, null is all of them.
  List<MoneyDay> monthDays({MoneyFlow? flow, DateTimeRange? range}) =>
      MoneyDay.group(_monthEntries(flow: flow, range: range));

  /// How many of this month's entries survive [flow] and [range] — what the
  /// filter chips and the day menu count.
  int monthCount({MoneyFlow? flow, DateTimeRange? range}) =>
      _monthEntries(flow: flow, range: range).length;

  /// What one side's surviving entries add up to — the quiet figure beside
  /// the filter chips, answering "and how much was that" for whatever cut
  /// the two filters have made.
  double filteredTotal({required MoneyFlow flow, DateTimeRange? range}) =>
      _monthEntries(flow: flow, range: range)
          .fold<double>(0, (sum, entry) => sum + entry.amount);

  /// This month's entries cut down to one side of the ledger, a run of days,
  /// or both.
  ///
  /// Both ends of [range] are inside it: somebody asking for the 1st to the
  /// 10th means the 10th as well, and the day is compared without its clock
  /// so an entry at 8pm on the last day is not pushed past the end.
  Iterable<PersonalTransaction> _monthEntries({
    MoneyFlow? flow,
    DateTimeRange? range,
  }) {
    final DateTime? from =
        range == null ? null : DateUtils.dateOnly(range.start);
    final DateTime? to = range == null ? null : DateUtils.dateOnly(range.end);

    return monthTransactions.where((entry) {
      if (flow != null && entry.flow != flow) return false;
      if (from != null && to != null) {
        final DateTime day = DateUtils.dateOnly(entry.day);
        if (day.isBefore(from) || day.isAfter(to)) return false;
      }
      return true;
    });
  }

  /// The first day anything was recorded — where "all time" begins. Null
  /// on an empty ledger.
  DateTime? get earliestEntry {
    if (transactions.isEmpty) return null;
    // The list is newest first, so the oldest is at the end — but read
    // rather than assumed, in case something ever hands it over otherwise.
    String earliest = transactions.first.date;
    for (final PersonalTransaction entry in transactions) {
      if (entry.date.compareTo(earliest) < 0) earliest = entry.date;
    }
    return DateTime.tryParse(earliest);
  }

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
      final String key = entry.category.isEmpty
          ? PersonalCategory.unknown.key
          : entry.category;
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
    String subcategory = '',
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
        subcategory: subcategory,
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

  /// ------------------------------------------------------------- categories

  /// Saves a category of the member's own and returns the key entries store
  /// it under, so the picker that just made one can select it. Null means
  /// nothing was written — the name was empty, or already taken.
  ///
  /// The name is checked against everything on that side of the picker,
  /// fixed labels included: two chips reading "Food" would be two piles for
  /// the same money, which is the thing categories exist to prevent.
  Future<String?> saveCategory({
    CustomCategory? existing,
    required bool income,
    required String name,
    required String iconKey,
    required String colorKey,
  }) async {
    if (userPhone.isEmpty) return null;

    final String clean = name.trim();
    if (clean.isEmpty) return null;

    // Against the member's own names as typed, and against the built-in
    // names in every language the app has — see [reservedNamesFor] for why
    // the current label alone would not hold.
    //
    // A category keeping its own name is exempt from all of it: the name
    // already stands, so it collides with nothing new — and a colour or
    // icon change must not be refused because the name it has always had
    // is one that could not be chosen today.
    final String lower = clean.toLowerCase();
    final bool keepsOwnName =
        existing != null && existing.name.trim().toLowerCase() == lower;
    final bool taken = !keepsOwnName &&
        (PersonalCategory.reservedNamesFor(income).contains(lower) ||
            customCategories.any((category) =>
                category.id != existing?.id &&
                category.isIncome == income &&
                category.name.trim().toLowerCase() == lower));
    if (taken) {
      CustomSnackbar.show(
          type: SnackbarType.info, message: 'category_name_exists'.tr);
      return null;
    }

    try {
      isSaving = true;
      update();

      final bool offline = _isOffline;

      final String id = await repository.saveCategory(CustomCategory(
        id: existing?.id ?? '',
        ownerPhone: userPhone,
        name: clean,
        flow: income ? MoneyFlow.income : MoneyFlow.expense,
        iconKey: iconKey,
        colorKey: colorKey,
      ));

      CustomSnackbar.show(
        type: offline ? SnackbarType.info : SnackbarType.success,
        message: offline
            ? 'saved_offline_generic'.tr
            : (existing == null ? 'category_added'.tr : 'category_updated'.tr),
      );
      return id;
    } catch (e) {
      debugPrint('Error saving custom category: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_save_category'.tr);
      return null;
    } finally {
      isSaving = false;
      update();
    }
  }

  /// Removes one of the member's own categories. Whatever was filed under it
  /// — the whole ledger's worth, not just this month's — moves to the fixed
  /// "other" bucket of its side, in the same write, so no entry is ever left
  /// pointing at a category that is gone.
  Future<bool> deleteCategory(CustomCategory category) async {
    try {
      final bool offline = _isOffline;

      await repository.deleteCategory(
        category.id,
        entries: transactions
            .where((entry) => entry.category == category.id)
            .toList(),
        subcategoryIds: subcategories
            .where((subcategory) => subcategory.parent == category.id)
            .map((subcategory) => subcategory.id)
            .toList(),
      );

      CustomSnackbar.show(
        type: offline ? SnackbarType.info : SnackbarType.success,
        message: offline ? 'saved_offline_generic'.tr : 'category_deleted'.tr,
      );
      return true;
    } catch (e) {
      debugPrint('Error deleting custom category: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_delete_category'.tr);
      return false;
    }
  }

  /// Writes the picker's new arrangement for one side, [keys] first to last.
  ///
  /// Optimistic, unlike every other write here: the registry takes the new
  /// order before Firestore has it, so the row the member just dropped does
  /// not snap back while the write settles. No toast either way — the list
  /// moving is its own confirmation, and a drag is too small an act to
  /// announce.
  Future<void> arrangeCategories({
    required bool income,
    required List<String> keys,
  }) async {
    if (userPhone.isEmpty) return;

    final CategoryOrder next = categoryOrder.withSide(income, keys);
    categoryOrder = next;
    PersonalCategory.registerOrder(next);
    update();

    try {
      await repository.saveCategoryOrder(userPhone, next);
    } catch (e) {
      debugPrint('Error saving category order: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_save_order'.tr);
    }
  }

  /// ---------------------------------------------------------- subcategories

  /// The finer cuts inside one category — however the member arranged them,
  /// and in the order they were made until they have. The saved order leads
  /// and whatever it has not met follows, the same bargain the category
  /// picker strikes: a deleted id is passed over, a new tag shows at the
  /// end.
  List<Subcategory> subcategoriesOf(String parent) {
    final Map<String, Subcategory> byId = {
      for (final Subcategory subcategory in subcategories)
        if (subcategory.parent == parent) subcategory.id: subcategory,
    };

    final List<Subcategory> arranged = [];
    for (final String id in categoryOrder.subsOf(parent)) {
      final Subcategory? subcategory = byId.remove(id);
      if (subcategory != null) arranged.add(subcategory);
    }
    arranged.addAll(byId.values);
    return arranged;
  }

  /// Writes one category's new subcategory arrangement, [ids] first to
  /// last. Optimistic and silent, exactly as [arrangeCategories] is, and
  /// for the same reasons.
  Future<void> arrangeSubcategories({
    required String parent,
    required List<String> ids,
  }) async {
    if (userPhone.isEmpty || parent.isEmpty) return;

    final CategoryOrder next = categoryOrder.withSubs(parent, ids);
    categoryOrder = next;
    PersonalCategory.registerOrder(next);
    update();

    try {
      await repository.saveCategoryOrder(userPhone, next);
    } catch (e) {
      debugPrint('Error saving subcategory order: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_save_order'.tr);
    }
  }

  /// Saves one of the member's subcategories and returns the id entries are
  /// tagged with. Null means nothing was written — the name was empty, or
  /// its category already has one by that name.
  Future<String?> saveSubcategory({
    Subcategory? existing,
    required String parent,
    required String name,
  }) async {
    if (userPhone.isEmpty || parent.isEmpty) return null;

    final String clean = name.trim();
    if (clean.isEmpty) return null;

    // Only within the parent: "bazar" inside food and "bazar" inside a
    // custom category are two different cuts, and neither is in the way of
    // the other.
    final String lower = clean.toLowerCase();
    final bool taken = subcategories.any((subcategory) =>
        subcategory.id != existing?.id &&
        subcategory.parent == parent &&
        subcategory.name.trim().toLowerCase() == lower);
    if (taken) {
      CustomSnackbar.show(
          type: SnackbarType.info, message: 'subcategory_name_exists'.tr);
      return null;
    }

    try {
      isSaving = true;
      update();

      final bool offline = _isOffline;

      final String id = await repository.saveSubcategory(Subcategory(
        id: existing?.id ?? '',
        ownerPhone: userPhone,
        parent: parent,
        name: clean,
      ));

      CustomSnackbar.show(
        type: offline ? SnackbarType.info : SnackbarType.success,
        message: offline
            ? 'saved_offline_generic'.tr
            : (existing == null
                ? 'subcategory_added'.tr
                : 'subcategory_updated'.tr),
      );
      return id;
    } catch (e) {
      debugPrint('Error saving subcategory: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_save_subcategory'.tr);
      return null;
    } finally {
      isSaving = false;
      update();
    }
  }

  /// Removes one subcategory. The entries tagged with it keep their category
  /// — only the tag comes off, in the same write.
  Future<bool> deleteSubcategory(Subcategory subcategory) async {
    try {
      final bool offline = _isOffline;

      await repository.deleteSubcategory(
        subcategory.id,
        entries: transactions
            .where((entry) => entry.subcategory == subcategory.id)
            .toList(),
      );

      CustomSnackbar.show(
        type: offline ? SnackbarType.info : SnackbarType.success,
        message:
            offline ? 'saved_offline_generic'.tr : 'subcategory_deleted'.tr,
      );
      return true;
    } catch (e) {
      debugPrint('Error deleting subcategory: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_delete_subcategory'.tr);
      return false;
    }
  }

  /// ------------------------------------------------------------ dena-paona

  /// One row per person, biggest outstanding first, settled accounts last.
  /// The people saved on their own come in too, so an account opened from the
  /// dues screen is on the list before a single taka has moved.
  List<PersonBalance> get people =>
      PersonBalance.group(debts, saved: savedPeople);

  PersonBalance? personFor(String key) {
    for (final PersonBalance person in people) {
      if (person.key == key) return person;
    }
    return null;
  }

  /// What the whole ledger comes to, both directions kept apart rather than
  /// netted — one number would hide both.
  ///
  /// [totalReceivable] is what the dues tab shows as "ধার নিয়েছি": loans
  /// taken, money that came into the wallet. [totalPayable] is "ধার দিয়েছি":
  /// loans given, money that went out. See [DebtFlow] for why the two read
  /// the opposite way round to their names here.
  double get totalReceivable => people
      .where((person) => person.owesMe)
      .fold<double>(0, (sum, person) => sum + person.balance);

  double get totalPayable => people
      .where((person) => !person.owesMe && !person.isSettled)
      .fold<double>(0, (sum, person) => sum + person.balance.abs());

  /// Names already in the ledger — the editor offers them so a second entry
  /// for the same person does not start a second account.
  List<String> get knownPeople => people
      .map((person) => person.name)
      .where((name) => name.isNotEmpty)
      .toList();

  /// The keys already on the dues list, for anything offering people to add:
  /// somebody who is on it once should not be offered as new.
  Set<String> get personKeys => people.map((person) => person.key).toSet();

  /// Opens an account with somebody, and nothing more.
  ///
  /// No amount, no note, no date — the person is the whole of it, and what
  /// passes between the two of them is entered afterwards from inside their
  /// account. Adding a name that is already on the list is not an error worth
  /// a red banner: it is the same account, so it is said plainly and left
  /// alone rather than duplicated.
  Future<bool> addPerson({
    required String name,
    String phone = '',
  }) async {
    if (userPhone.isEmpty) return false;

    final String cleanName = name.trim();
    final String cleanPhone = phone.trim();
    if (cleanName.isEmpty) return false;

    final String key =
        cleanPhone.isNotEmpty ? cleanPhone : cleanName.toLowerCase();
    if (personKeys.contains(key)) {
      CustomSnackbar.show(
          type: SnackbarType.info, message: 'person_already_added'.tr);
      return false;
    }

    try {
      isSaving = true;
      update();

      final bool offline = _isOffline;

      await repository.savePerson(LedgerPerson(
        ownerPhone: userPhone,
        name: cleanName,
        phone: cleanPhone,
      ));

      CustomSnackbar.show(
        type: offline ? SnackbarType.info : SnackbarType.success,
        message: offline ? 'saved_offline_generic'.tr : 'person_added'.tr,
      );
      return true;
    } catch (e) {
      debugPrint('Error saving ledger person: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_save_person'.tr);
      return false;
    } finally {
      isSaving = false;
      update();
    }
  }

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

  /// Renames the person a whole account is kept with.
  ///
  /// Returns the key the account is grouped under afterwards, so the screen
  /// that asked can follow it: with no phone the key is folded out of the
  /// name, and a renamed person is therefore at a new one. Null means nothing
  /// was written — the name was empty, or already taken.
  ///
  /// A rename onto a name somebody else on the list already uses is refused
  /// rather than applied. It would fold the two accounts into one, which is a
  /// merge; nobody typing a new spelling is asking for their entries to be
  /// mixed with another person's, and it cannot be undone by renaming back.
  Future<String?> renamePerson(PersonBalance person, String name) async {
    if (userPhone.isEmpty) return null;

    final String clean = name.trim();
    if (clean.isEmpty) return null;

    // Same spelling: nothing to write, and nothing to complain about either.
    if (clean == person.name.trim()) return person.key;

    // The rule [DebtEntry.personKey] uses, applied to what the name is about
    // to become.
    final String phone = person.phone.trim();
    final String key = phone.isNotEmpty ? phone : clean.toLowerCase();

    if (key != person.key && personKeys.contains(key)) {
      CustomSnackbar.show(
          type: SnackbarType.info, message: 'person_already_added'.tr);
      return null;
    }

    try {
      isSaving = true;
      update();

      final bool offline = _isOffline;

      await repository.renamePerson(
        entries: person.entries,
        personIds: savedPeople
            .where((saved) => saved.key == person.key)
            .map((saved) => saved.id)
            .toList(),
        name: clean,
      );

      CustomSnackbar.show(
        type: offline ? SnackbarType.info : SnackbarType.success,
        message: offline ? 'saved_offline_generic'.tr : 'person_renamed'.tr,
      );
      return key;
    } catch (e) {
      debugPrint('Error renaming ledger person: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_save_person'.tr);
      return null;
    } finally {
      isSaving = false;
      update();
    }
  }

  /// Clears one person's whole account — every row, not a settling entry, and
  /// the person themselves, or the row would come back empty on the next
  /// snapshot.
  Future<void> deletePerson(PersonBalance person) async {
    try {
      await repository.deletePerson(
        person.entries,
        personIds: savedPeople
            .where((saved) => saved.key == person.key)
            .map((saved) => saved.id)
            .toList(),
      );
      CustomSnackbar.show(
          type: SnackbarType.success, message: 'person_removed'.tr);
    } catch (e) {
      debugPrint('Error deleting person ledger: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_delete_entry'.tr);
    }
  }
}
