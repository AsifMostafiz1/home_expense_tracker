class UserModel {
  final String name;
  final String phone;
  final String password;
  final String? profileImage;
  final String isAdmin;

  UserModel({
    required this.name,
    required this.phone,
    required this.password,
    this.profileImage,
    this.isAdmin = '0',
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      password: map['password'] ?? '',
      profileImage: map['profileImage'],
      isAdmin: map['isAdmin'] ?? '0',
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
