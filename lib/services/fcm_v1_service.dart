import 'package:flutter/services.dart';
// auth_io by name, but `obtainAccessCredentialsViaServiceAccount` is pure
// Dart — it is simply the library that exports it.
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

class FcmV1Service {
  static final FcmV1Service _instance = FcmV1Service._internal();
  factory FcmV1Service() => _instance;
  FcmV1Service._internal();

  final List<String> _scopes = [
    'https://www.googleapis.com/auth/firebase.messaging',
  ];

  Future<String> getAccessToken() async {
    try {
      final jsonString = await rootBundle.loadString('service_account.json');
      final accountCredentials = ServiceAccountCredentials.fromJson(jsonString);

      // The credentials exchange, on a client made here rather than through
      // `clientViaServiceAccount`: that helper builds a dart:io transport and
      // throws on web, while `http.Client()` picks the right one per platform.
      final http.Client client = http.Client();
      try {
        final AccessCredentials credentials =
            await obtainAccessCredentialsViaServiceAccount(
                accountCredentials, _scopes, client);
        return credentials.accessToken.data;
      } finally {
        client.close();
      }
    } catch (e) {
      print('Error getting FCM v1 access token: $e');
      return '';
    }
  }
}
