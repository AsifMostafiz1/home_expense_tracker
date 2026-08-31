import 'package:flutter/material.dart';

class ExpenseModel {
  String id;
  String description;
  double amount;
  DateTime date;
  TimeOfDay time;
  String userName;
  String userPhone;
  String type; // 'expense' or 'others'

  /// Public URL of the receipt photo, when one was attached. Optional: most
  /// entries are typed from memory and never have one.
  String? imageUrl;

  /// True while the entry — or an edit to it — is stored on this device only,
  /// waiting for a connection to reach the server. Read off Firestore's own
  /// queue, so it survives a restart and clears by itself once delivered.
  bool isPending;

  /// A receipt picked while offline, still on this device: its upload is
  /// waiting in the outbox. Set by the controller, never stored — the server
  /// only ever learns the URL, once there is one.
  String? pendingReceiptPath;

  ExpenseModel({
    required this.id,
    required this.description,
    required this.amount,
    required this.date,
    required this.time,
    required this.userName,
    required this.userPhone,
    required this.type,
    this.imageUrl,
    this.isPending = false,
    this.pendingReceiptPath,
  });

  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  bool get hasPendingReceipt =>
      pendingReceiptPath != null && pendingReceiptPath!.isNotEmpty;

  /// Something to show for the receipt — uploaded, or waiting to be.
  bool get hasAnyReceipt => hasImage || hasPendingReceipt;

  factory ExpenseModel.fromMap(
    String id,
    Map<String, dynamic> map, {
    bool isPending = false,
  }) {
    return ExpenseModel(
      id: id,
      description: map['description'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      date: DateTime.parse(map['date']),
      time: TimeOfDay(
        hour: map['time_hour'] ?? 0,
        minute: map['time_minute'] ?? 0,
      ),
      userName: map['user_name'] ?? '',
      userPhone: map['user_phone'] ?? '',
      type: map['type'] ?? 'expense',
      imageUrl: map['image_url'],
      isPending: isPending,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'description': description,
      'amount': amount,
      'date': date.toIso8601String(),
      'time_hour': time.hour,
      'time_minute': time.minute,
      'user_name': userName,
      'user_phone': userPhone,
      'type': type,
      'image_url': imageUrl,
    };
  }
}
