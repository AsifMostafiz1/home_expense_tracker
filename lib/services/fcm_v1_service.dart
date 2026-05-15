import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';

class FcmV1Service {
  static final FcmV1Service _instance = FcmV1Service._internal();
  factory FcmV1Service() => _instance;
  FcmV1Service._internal();

  final List<String> _scopes = [
    'https://www.googleapis.com/auth/firebase.messaging',
  ];

  Future<String> getAccessToken() async {
    try {
      final jsonString = await rootBundle.loadString('assets/service_account.json');
      final accountCredentials = ServiceAccountCredentials.fromJson(jsonString);

      final authClient = await clientViaServiceAccount(accountCredentials, _scopes);
      final accessToken = authClient.credentials.accessToken.data;
      
      authClient.close();
      return accessToken;
    } catch (e) {
      print('Error getting FCM v1 access token: $e');
      return '';
    }
  }
}
