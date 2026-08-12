import '../model/member_model.dart';

abstract class MemberRepository {
  Stream<List<MemberModel>> getMembersStream();

  /// Marks the account removed.
  ///
  /// The record is kept as a tombstone rather than deleted, for two reasons:
  /// sign-up looks a phone number up before allowing registration, so a
  /// deleted number could simply be registered again; and keeping the row
  /// preserves who removed whom.
  Future<void> removeMember(String phone, String removedBy);

  /// Grants or revokes admin rights. Stored as the same `'1'` / `'0'` string
  /// the sign-in flow already writes into local preferences.
  Future<void> setAdminRole(String phone, bool isAdmin, String changedBy);
}
