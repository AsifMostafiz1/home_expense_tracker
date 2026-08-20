import '../model/debt_entry.dart';
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

  /// Removes every row kept with one person — the "this account is finished"
  /// action, which is a delete of the history rather than a settling entry.
  Future<void> deletePerson(List<DebtEntry> entries);
}
