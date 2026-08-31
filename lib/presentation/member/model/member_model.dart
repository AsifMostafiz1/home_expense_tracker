import '../../../utils/app_constant.dart';

class MemberModel {
  final String name;
  final String phone;
  final String isAdmin;
  final String? profileImage;

  /// 'meal' or 'general'. A document without the field is a meal user, so
  /// every account that predates the field keeps its full access.
  final String userType;

  /// Tombstoned by an admin — kept in Firestore so the phone number cannot be
  /// registered again, but no longer a member of the house.
  final bool isRemoved;

  MemberModel({
    required this.name,
    required this.phone,
    this.isAdmin = '0',
    this.profileImage,
    this.userType = AppConstant.userTypeMeal,
    this.isRemoved = false,
  });

  bool get isAdminUser => isAdmin == '1';

  /// Personal wallet only — no meals, no shared expenses, no house bills.
  bool get isGeneralUser => userType == AppConstant.userTypeGeneral;

  factory MemberModel.fromMap(Map<String, dynamic> map) {
    return MemberModel(
      name: map['name'] ?? 'Unknown',
      phone: map['phone'] ?? 'No Phone',
      isAdmin: map['isAdmin'] ?? '0',
      profileImage: map['profileImage'],
      userType: map['userType'] == AppConstant.userTypeGeneral
          ? AppConstant.userTypeGeneral
          : AppConstant.userTypeMeal,
      isRemoved: map['removed'] == true,
    );
  }
}
