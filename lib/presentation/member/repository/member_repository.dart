import '../model/member_model.dart';

abstract class MemberRepository {
  Stream<List<MemberModel>> getMembersStream();
}
