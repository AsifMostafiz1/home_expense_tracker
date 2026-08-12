class MemberModel {
  final String name;
  final String phone;
  final String isAdmin;
  final String? profileImage;

  /// Tombstoned by an admin — kept in Firestore so the phone number cannot be
  /// registered again, but no longer a member of the house.
  final bool isRemoved;

  MemberModel({
    required this.name,
    required this.phone,
    this.isAdmin = '0',
    this.profileImage,
    this.isRemoved = false,
  });

  bool get isAdminUser => isAdmin == '1';

  factory MemberModel.fromMap(Map<String, dynamic> map) {
    return MemberModel(
      name: map['name'] ?? 'Unknown',
      phone: map['phone'] ?? 'No Phone',
      isAdmin: map['isAdmin'] ?? '0',
      profileImage: map['profileImage'],
      isRemoved: map['removed'] == true,
    );
  }
}
