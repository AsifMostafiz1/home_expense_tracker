import 'package:firebase_core/firebase_core.dart';

/// Firebase configuration for the web build.
///
/// Android and iOS read theirs from `google-services.json` /
/// `GoogleService-Info.plist` at build time; the web has no such file, so
/// `Firebase.initializeApp` must be handed the options explicitly.
///
/// Everything below except [_appId] comes straight from the project itself
/// (the same values `google-services.json` carries). The appId is currently
/// the *Android* app's id standing in, because no web app has been registered
/// on the Firebase project yet — Firestore and Auth only use the apiKey and
/// projectId, so they work regardless. To do it properly: Firebase console →
/// Project settings → Your apps → Add app → Web, then paste that app's
/// `appId` (it looks like `1:266523005752:web:...`) over the stand-in.
class FirebaseWebConfig {
  FirebaseWebConfig._();

  static const String _appId = '1:266523005752:android:bd6f639a7fafe29e4ba7cd';

  static const FirebaseOptions options = FirebaseOptions(
    apiKey: 'AIzaSyDvl33PZVTjgdgwomRs8ORP4qFXPDCrktA',
    appId: _appId,
    messagingSenderId: '266523005752',
    projectId: 'home-expense-tracker-54c89',
    authDomain: 'home-expense-tracker-54c89.firebaseapp.com',
    storageBucket: 'home-expense-tracker-54c89.firebasestorage.app',
  );
}
