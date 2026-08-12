class UserModel {
  final String name;
  final String phone;
  final String password;
  final String? profileImage;
  final String isAdmin;

  /// Set when an admin removed this member. The record is kept so the phone
  /// number cannot be registered again, but the account can no longer sign in.
  final bool isRemoved;

  UserModel({
    required this.name,
    required this.phone,
    required this.password,
    this.profileImage,
    this.isAdmin = '0',
    this.isRemoved = false,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      password: map['password'] ?? '',
      profileImage: map['profileImage'],
      isAdmin: map['isAdmin'] ?? '0',
      isRemoved: map['removed'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'password': password,
      'profileImage': profileImage,
      'isAdmin': isAdmin,
    };
  }
}
