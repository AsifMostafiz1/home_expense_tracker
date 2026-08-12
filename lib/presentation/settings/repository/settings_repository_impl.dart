import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../utils/app_constant.dart';
import '../../member/model/member_model.dart';
import '../model/monthly_bill_model.dart';
import 'settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  @override
  Future<List<MonthlyBillModel>> fetchMonthlyBills() async {
    QuerySnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore
        .instance
        .collection(AppConstant.collectionMonthlyBills)
        .get();

    List<MonthlyBillModel> bills = snapshot.docs
        .map((doc) => MonthlyBillModel.fromMap(doc.id, doc.data()))
        .toList();

    // Sorted here rather than with `orderBy(documentId, descending)`, which
    // Firestore refuses without a hand-built index. The `YYYY-MM` key sorts
    // chronologically on its own, and a house has one document per month.
    bills.sort((a, b) => b.id.compareTo(a.id));
    return bills;
  }

  @override
  Future<List<MemberModel>> fetchActiveMembers() async {
    QuerySnapshot<Map<String, dynamic>> snapshot = await FirebaseFirestore
        .instance
        .collection(AppConstant.collectionUsers)
        .get();

    return _membersOf(snapshot);
  }

  @override
  Stream<List<MemberModel>> watchActiveMembers() {
    return FirebaseFirestore.instance
        .collection(AppConstant.collectionUsers)
        .snapshots()
        .map(_membersOf);
  }

  List<MemberModel> _membersOf(QuerySnapshot<Map<String, dynamic>> snapshot) {
    List<MemberModel> members = snapshot.docs
        .map((doc) => MemberModel.fromMap(doc.data()))
        // Removed accounts stay in Firestore as tombstones; they no longer
        // share the bills.
        .where((member) => !member.isRemoved)
        .toList();

    members.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return members;
  }

  @override
  Future<void> saveMonthlyBill(
      String monthKey, Map<String, dynamic> data) async {
    await FirebaseFirestore.instance
        .collection(AppConstant.collectionMonthlyBills)
        .doc(monthKey)
        .set({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> deleteMonthlyBill(String monthKey) async {
    await FirebaseFirestore.instance
        .collection(AppConstant.collectionMonthlyBills)
        .doc(monthKey)
        .delete();
  }
}
