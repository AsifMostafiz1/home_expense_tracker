import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../utils/app_constant.dart';
import '../model/member_model.dart';
import 'member_repository.dart';

class MemberRepositoryImpl implements MemberRepository {
  @override
  Stream<List<MemberModel>> getMembersStream() {
    return FirebaseFirestore.instance
        .collection(AppConstant.collectionUsers)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => MemberModel.fromMap(doc.data()))
          // Removed accounts stay in Firestore as tombstones; they are not
          // members any more, so they never reach the list.
          .where((member) => !member.isRemoved)
          .toList();
    });
  }

  @override
  Future<void> setAdminRole(
      String phone, bool isAdmin, String changedBy) async {
    await FirebaseFirestore.instance
        .collection(AppConstant.collectionUsers)
        .doc(phone)
        .set({
      'isAdmin': isAdmin ? '1' : '0',
      'role_changed_by': changedBy,
      'role_changed_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> setUserType(
      String phone, String userType, String changedBy) async {
    await FirebaseFirestore.instance
        .collection(AppConstant.collectionUsers)
        .doc(phone)
        .set({
      'userType': userType,
      'type_changed_by': changedBy,
      'type_changed_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> removeMember(String phone, String removedBy) async {
    await FirebaseFirestore.instance
        .collection(AppConstant.collectionUsers)
        .doc(phone)
        .set({
      'removed': true,
      'removed_by': removedBy,
      'removed_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
