import 'package:flutter/material.dart';

class ExpenseModel {
  String id;
  String description;
  double amount;
  DateTime date;
  TimeOfDay time;
  String userName;
  String userPhone;

  ExpenseModel({
    required this.id,
    required this.description,
    required this.amount,
    required this.date,
    required this.time,
    required this.userName,
    required this.userPhone,
  });

  factory ExpenseModel.fromMap(String id, Map<String, dynamic> map) {
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
    };
  }
}
