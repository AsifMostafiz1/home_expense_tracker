import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:demo_project/presentation/auth/view/sign_in_screen.dart';
import 'package:demo_project/presentation/dashboard/view/dashboard_screen.dart';
import 'package:demo_project/utils/app_constant.dart';
import 'package:demo_project/utils/app_theme.dart';
import 'package:demo_project/common/binding/initial_binding.dart';
import 'package:demo_project/services/push_notification_service.dart';
import 'package:demo_project/utils/app_translations.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
      appleProvider: AppleProvider.debug,
    );
    
    // Anonymous sign-in to provide auth token for Firebase Storage/Firestore
    if (FirebaseAuth.instance.currentUser == null) {
      await FirebaseAuth.instance.signInAnonymously();
    }
    
    await PushNotificationService().init();
  } catch (e) {
    debugPrint("Firebase initialization failed: $e");
  }
  
  SharedPreferences prefs = await SharedPreferences.getInstance();
  bool isLoggedIn = prefs.getBool(AppConstant.keyIsLoggedIn) ?? false;
  
  String themeStr = prefs.getString(AppConstant.keyThemeMode) ?? 'system';
  ThemeMode themeMode = ThemeMode.system;
  if (themeStr == 'light') themeMode = ThemeMode.light;
  else if (themeStr == 'dark') themeMode = ThemeMode.dark;

  String lang = prefs.getString(AppConstant.keyLanguage) ?? 'en';
  Locale locale = lang == 'bn' ? const Locale('bn', 'BD') : const Locale('en', 'US');

  runApp(MyApp(isLoggedIn: isLoggedIn, themeMode: themeMode, locale: locale));
}

class MyApp extends StatelessWidget {
  final bool isLoggedIn;
  final ThemeMode themeMode;
  final Locale locale;
  
  const MyApp({super.key, required this.isLoggedIn, required this.themeMode, required this.locale});

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: 'Home Expense Tracker',
      debugShowCheckedModeBanner: false,
      translations: AppTranslations(),
      locale: locale,
      fallbackLocale: const Locale('en', 'US'),
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,
      initialBinding: InitialBinding(),
      home: isLoggedIn ? const DashboardScreen() : const SignInScreen(),
    );
  }
}

