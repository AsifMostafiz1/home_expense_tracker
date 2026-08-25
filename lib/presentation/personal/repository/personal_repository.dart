import '../model/debt_entry.dart';
import '../model/ledger_person.dart';
import '../model/personal_transaction.dart';

/// One member's private books. Every method is scoped to their phone — there
/// is no call here that can read or write anybody else's ledger.
abstract class PersonalRepository {
  Stream<List<PersonalTransaction>> watchTransactions(String ownerPhone);

  Future<void> saveTransaction(PersonalTransaction transaction);

  Future<void> deleteTransaction(String id);

  Stream<List<DebtEntry>> watchDebts(String ownerPhone);

  Future<void> saveDebtEntry(DebtEntry entry);

  Future<void> deleteDebtEntry(String id);

  /// The people accounts are kept with, saved before any money moves so one
  /// can be opened from the dues screen on its own.
  Stream<List<LedgerPerson>> watchPeople(String ownerPhone);

  Future<void> savePerson(LedgerPerson person);

  /// Removes every row kept with one person — the "this account is finished"
  /// action, which is a delete of the history rather than a settling entry.
  /// [personIds] are that person's saved records, cleared in the same batch
  /// so the row does not come back empty.
  Future<void> deletePerson(
    List<DebtEntry> entries, {
    List<String> personIds,
  });
}
