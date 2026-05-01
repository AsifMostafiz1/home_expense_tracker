import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../utils/app_constant.dart';
import '../model/expense_model.dart';
import 'expense_repository.dart';

class ExpenseRepositoryImpl implements ExpenseRepository {
  @override
  Future<List<ExpenseModel>> fetchExpenses(String userPhone) async {
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection(AppConstant.collectionExpenses)
        .where('user_phone', isEqualTo: userPhone)
        .get();

    return snapshot.docs.map((doc) {
      return ExpenseModel.fromMap(doc.id, doc.data() as Map<String, dynamic>);
    }).toList();
  }

  @override
  Future<void> addExpense(Map<String, dynamic> data) async {
    await FirebaseFirestore.instance
        .collection(AppConstant.collectionExpenses)
        .add(data);
  }

  @override
  Future<void> updateExpense(String expenseId, Map<String, dynamic> data) async {
    await FirebaseFirestore.instance
        .collection(AppConstant.collectionExpenses)
        .doc(expenseId)
        .update(data);
  }

  @override
  Future<void> deleteExpense(String expenseId) async {
    await FirebaseFirestore.instance
        .collection(AppConstant.collectionExpenses)
        .doc(expenseId)
        .delete();
  }
}
