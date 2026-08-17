import 'package:cloud_firestore/cloud_firestore.dart';

class EditLogModel {
  /// Every [type] the app writes today, in the order the history screen
  /// offers them as filters. Anything else is still shown, just untinted.
  static const List<String> knownTypes = ['meal', 'expense', 'role', 'member'];

  String id;
  String adminName;
  String adminPhone;
  String targetUserName;
  String targetUserPhone;
  String type; // 'meal' or 'expense'
  String description;
  DateTime createdAt;

  EditLogModel({
    required this.id,
    required this.adminName,
    required this.adminPhone,
    required this.targetUserName,
    required this.targetUserPhone,
    required this.type,
    required this.description,
    required this.createdAt,
  });

  factory EditLogModel.fromMap(String id, Map<String, dynamic> map) {
    return EditLogModel(
      id: id,
      adminName: map['adminName'] ?? '',
      adminPhone: map['adminPhone'] ?? '',
      targetUserName: map['targetUserName'] ?? '',
      targetUserPhone: map['targetUserPhone'] ?? '',
      type: map['type'] ?? '',
      description: map['description'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'adminName': adminName,
      'adminPhone': adminPhone,
      'targetUserName': targetUserName,
      'targetUserPhone': targetUserPhone,
      'type': type,
      'description': description,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
