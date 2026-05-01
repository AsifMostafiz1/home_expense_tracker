import '../model/expense_model.dart';

abstract class ExpenseRepository {
  Future<List<ExpenseModel>> fetchExpenses(String userPhone);
  Future<void> addExpense(Map<String, dynamic> data);
  Future<void> updateExpense(String expenseId, Map<String, dynamic> data);
  Future<void> deleteExpense(String expenseId);
}
