class UserModel {
  final String name;
  final String phone;
  final String password;
  final String? profileImage;

  UserModel({
    required this.name,
    required this.phone,
    required this.password,
    this.profileImage,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      password: map['password'] ?? '',
      profileImage: map['profileImage'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'password': password,
      'profileImage': profileImage,
    };
  }
}
