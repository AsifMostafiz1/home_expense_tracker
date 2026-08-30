import '../model/custom_category.dart';
import '../model/debt_entry.dart';
import '../model/ledger_person.dart';
import '../model/personal_transaction.dart';
import '../model/subcategory.dart';

/// One member's private books. Every method is scoped to their phone — there
/// is no call here that can read or write anybody else's ledger.
abstract class PersonalRepository {
  Stream<List<PersonalTransaction>> watchTransactions(String ownerPhone);

  Future<void> saveTransaction(PersonalTransaction transaction);

  Future<void> deleteTransaction(String id);

  /// The categories this member made for themselves, beside the fixed list.
  Stream<List<CustomCategory>> watchCategories(String ownerPhone);

  /// Returns the category's document id — known before the write lands, so
  /// the sheet that just made one can select it at once, online or off.
  Future<String> saveCategory(CustomCategory category);

  /// Removes one custom category and refiles [entries] — the transactions
  /// still pointing at it — each under the fixed "other" bucket of its own
  /// side, batched so the category is never gone while entries still name
  /// it. The category's own subcategories go with it, [subcategoryIds], and
  /// the refiled entries lose their subcategory tag in the same write.
  Future<void> deleteCategory(
    String id, {
    required List<PersonalTransaction> entries,
    List<String> subcategoryIds = const [],
  });

  /// How this member arranged their picker — the default order until they
  /// first drag something.
  Stream<CategoryOrder> watchCategoryOrder(String ownerPhone);

  Future<void> saveCategoryOrder(String ownerPhone, CategoryOrder order);

  /// The finer cuts this member keeps inside their categories, all of them
  /// in one stream — a picker groups them by parent in memory.
  Stream<List<Subcategory>> watchSubcategories(String ownerPhone);

  /// Returns the subcategory's document id, known before the write lands —
  /// same contract as `saveCategory`.
  Future<String> saveSubcategory(Subcategory subcategory);

  /// Removes one subcategory and unties [entries] — the transactions still
  /// tagged with it — in the same batch. The entries keep their category;
  /// only the tag comes off.
  Future<void> deleteSubcategory(
    String id, {
    required List<PersonalTransaction> entries,
  });

  /// Writes a fresh account's starter subcategories and marks the account
  /// dealt, one batch for both so neither can land without the other.
  /// [seeds] carry their own document ids; an empty list just sets the
  /// mark — the account brought its own subcategories.
  Future<void> seedSubcategories(String ownerPhone, List<Subcategory> seeds);

  Stream<List<DebtEntry>> watchDebts(String ownerPhone);

  Future<void> saveDebtEntry(DebtEntry entry);

  Future<void> deleteDebtEntry(String id);

  /// The people accounts are kept with, saved before any money moves so one
  /// can be opened from the dues screen on its own.
  Stream<List<LedgerPerson>> watchPeople(String ownerPhone);

  Future<void> savePerson(LedgerPerson person);

  /// Writes one new name across a whole account.
  ///
  /// Every row carries the name it was made with — and with no phone to group
  /// on, the account's key is folded out of that name — so a rename has to
  /// reach all of them at once or it splits the account rather than renaming
  /// it. [personIds] are the person's saved records, in the same batch.
  Future<void> renamePerson({
    required List<DebtEntry> entries,
    List<String> personIds,
    required String name,
  });

  /// Removes every row kept with one person — the "this account is finished"
  /// action, which is a delete of the history rather than a settling entry.
  /// [personIds] are that person's saved records, cleared in the same batch
  /// so the row does not come back empty.
  Future<void> deletePerson(
    List<DebtEntry> entries, {
    List<String> personIds,
  });
}
