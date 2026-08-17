import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Narrowed import: the package also exports `User`, `AuthState` and friends,
// which would collide with the firebase_auth symbols above.
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import 'package:demo_project/utils/supabase_config.dart';
import 'package:demo_project/presentation/auth/view/sign_in_screen.dart';
import 'package:demo_project/presentation/dashboard/view/dashboard_screen.dart';
import 'package:demo_project/utils/app_constant.dart';
import 'package:demo_project/utils/app_theme.dart';
import 'package:demo_project/common/binding/initial_binding.dart';
import 'package:demo_project/services/push_notification_service.dart';
import 'package:demo_project/services/notification_permission_service.dart';
import 'package:demo_project/utils/app_translations.dart';

import 'package:demo_project/presentation/splash/view/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    print('FCM: Activating Firebase App Check...');
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.debug,
      appleProvider: AppleProvider.debug,
    );
    print('FCM: Firebase App Check activated.');

    // Anonymous sign-in to provide auth token for Firebase Storage/Firestore.
    //
    // Caught on its own: with anonymous auth switched off in the console this
    // throws `admin-restricted-operation`, and sharing a catch with the push
    // setup below meant one disabled toggle silently took notifications down
    // with it — no listeners, no topic subscriptions, no messages.
    if (FirebaseAuth.instance.currentUser == null) {
      try {
        await FirebaseAuth.instance.signInAnonymously();
      } catch (e) {
        debugPrint('Anonymous sign-in failed: $e');
      }
    }

    print('FCM: Starting PushNotificationService initialization...');
    await PushNotificationService().init();
  } catch (e) {
    debugPrint("Firebase initialization failed: $e");
  }

  // Supabase covers file/image storage only — Firestore is still the database.
  // Firebase Storage needs a billing account on the project, which this one
  // does not have. Kept outside the Firebase block, for the same reason the
  // anonymous sign-in above is: one failing service should not take the rest
  // of startup down with it.
  if (SupabaseConfig.isConfigured) {
    try {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        publishableKey: SupabaseConfig.publishableKey,
      );
    } catch (e) {
      debugPrint('Supabase initialization failed: $e');
    }
  } else {
    debugPrint('Supabase not configured — uploads are disabled.');
  }

  SharedPreferences prefs = await SharedPreferences.getInstance();
  
  String themeStr = prefs.getString(AppConstant.keyThemeMode) ?? 'system';
  ThemeMode themeMode = ThemeMode.system;
  if (themeStr == 'light') themeMode = ThemeMode.light;
  else if (themeStr == 'dark') themeMode = ThemeMode.dark;

  String lang = prefs.getString(AppConstant.keyLanguage) ?? 'en';
  Locale locale = lang == 'bn' ? const Locale('bn', 'BD') : const Locale('en', 'US');

  runApp(MyApp(themeMode: themeMode, locale: locale));
}

class MyApp extends StatefulWidget {
  final ThemeMode themeMode;
  final Locale locale;

  const MyApp({super.key, required this.themeMode, required this.locale});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only the trip back from system settings is worth re-checking. Prompting
    // on every resume would fire the dialog after any incidental app switch.
    if (state == AppLifecycleState.resumed &&
        NotificationPermissionService().awaitingSettingsReturn) {
      NotificationPermissionService().refreshAfterSettingsReturn();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GetMaterialApp(
      title: AppConstant.appName,
      debugShowCheckedModeBanner: false,
      translations: AppTranslations(),
      locale: widget.locale,
      fallbackLocale: const Locale('en', 'US'),
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: widget.themeMode,
      initialBinding: InitialBinding(),
      home: const SplashScreen(),
    );
  }
}

