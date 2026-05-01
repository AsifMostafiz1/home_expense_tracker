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
      return snapshot.docs.map((doc) {
        return MemberModel.fromMap(doc.data() as Map<String, dynamic>);
      }).toList();
    });
  }
}
