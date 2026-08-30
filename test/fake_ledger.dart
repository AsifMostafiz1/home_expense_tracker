import 'package:demo_project/presentation/personal/model/custom_category.dart';
import 'package:demo_project/presentation/personal/model/debt_entry.dart';
import 'package:demo_project/presentation/personal/model/ledger_person.dart';
import 'package:demo_project/presentation/personal/model/personal_transaction.dart';
import 'package:demo_project/presentation/personal/model/subcategory.dart';
import 'package:demo_project/presentation/personal/repository/personal_repository.dart';

/// The ledger, with no Firestore behind it — the screen only ever sees two
/// streams, so a fake is a pair of values.
class FakeLedger implements PersonalRepository {
  final List<PersonalTransaction> rows;
  final List<DebtEntry> dues;
  final List<Subcategory> subs;

  FakeLedger(this.rows, {this.dues = const [], this.subs = const []});

  @override
  Stream<List<PersonalTransaction>> watchTransactions(String ownerPhone) =>
      Stream<List<PersonalTransaction>>.value(rows);

  @override
  Stream<List<DebtEntry>> watchDebts(String ownerPhone) =>
      Stream<List<DebtEntry>>.value(dues);

  @override
  Future<void> saveTransaction(PersonalTransaction transaction) async {}

  @override
  Future<void> deleteTransaction(String id) async {}

  @override
  Future<void> saveDebtEntry(DebtEntry entry) async {}

  @override
  Future<void> deleteDebtEntry(String id) async {}

  @override
  Stream<List<LedgerPerson>> watchPeople(String ownerPhone) =>
      Stream<List<LedgerPerson>>.value(const []);

  @override
  Future<void> savePerson(LedgerPerson person) async {}

  @override
  Future<void> renamePerson({
    required List<DebtEntry> entries,
    List<String> personIds = const [],
    required String name,
  }) async {}

  @override
  Future<void> deletePerson(
    List<DebtEntry> entries, {
    List<String> personIds = const [],
  }) async {}

  @override
  Stream<List<CustomCategory>> watchCategories(String ownerPhone) =>
      Stream<List<CustomCategory>>.value(const []);

  @override
  Future<String> saveCategory(CustomCategory category) async => category.id;

  @override
  Future<void> deleteCategory(
    String id, {
    required List<PersonalTransaction> entries,
    List<String> subcategoryIds = const [],
  }) async {}

  @override
  Stream<CategoryOrder> watchCategoryOrder(String ownerPhone) =>
      Stream<CategoryOrder>.value(const CategoryOrder());

  @override
  Future<void> saveCategoryOrder(String ownerPhone, CategoryOrder order) async {}

  @override
  Stream<List<Subcategory>> watchSubcategories(String ownerPhone) =>
      Stream<List<Subcategory>>.value(subs);

  @override
  Future<String> saveSubcategory(Subcategory subcategory) async =>
      subcategory.id;

  @override
  Future<String> ensureSubcategory(Subcategory subcategory) async =>
      subs
          .firstWhere(
            (sub) =>
                sub.id == subcategory.id ||
                (sub.parent == subcategory.parent &&
                    sub.name.toLowerCase() == subcategory.name.toLowerCase()),
            orElse: () => subcategory,
          )
          .id;

  @override
  Future<void> deleteSubcategory(
    String id, {
    required List<PersonalTransaction> entries,
  }) async {}

  @override
  Future<void> seedSubcategories(
    String ownerPhone,
    List<Subcategory> seeds,
  ) async {}
}
