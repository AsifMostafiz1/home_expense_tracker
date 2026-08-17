import '../model/expense_model.dart';

abstract class ExpenseRepository {
  /// [fromCache] reads what the device already holds — instant, works with no
  /// network, and includes every entry saved while offline. The default goes
  /// to the server and fails when it cannot be reached.
  Future<List<ExpenseModel>> fetchExpenses(
    String userPhone, {
    bool fromCache = false,
  });

  /// Returns the new entry's id. Like [updateExpense] and [deleteExpense], it
  /// completes as soon as the write is stored on the device: offline, the
  /// entry is queued and delivered when the connection returns.
  Future<String> addExpense(Map<String, dynamic> data);

  Future<void> updateExpense(String expenseId, Map<String, dynamic> data);

  Future<void> deleteExpense(String expenseId);
}
