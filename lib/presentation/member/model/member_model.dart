class MemberModel {
  final String name;
  final String phone;

  MemberModel({
    required this.name,
    required this.phone,
  });

  factory MemberModel.fromMap(Map<String, dynamic> map) {
    return MemberModel(
      name: map['name'] ?? 'Unknown',
      phone: map['phone'] ?? 'No Phone',
    );
  }
}
