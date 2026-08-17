import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:demo_project/common/widgets/connection_banner.dart';
import 'package:demo_project/services/background_sync_service.dart';
import 'package:demo_project/services/push_notification_service.dart';
import 'package:demo_project/services/notification_permission_service.dart';
import 'package:demo_project/utils/app_translations.dart';

import 'package:demo_project/presentation/splash/view/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();

    // Offline support rests on this. Firestore keeps a local copy of what it
    // has read and a queue of what it has not yet delivered, so the app opens
    // and expenses can be entered with no connection; the queue drains on its
    // own once one returns. It is on by default on mobile — set explicitly so
    // nobody has to guess, and so it stays on if the default ever changes.
    // Must come before the first Firestore call.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
    );

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
    //
    // Bounded: this too runs before runApp(), and a link that is up but not
    // answering would otherwise hold the whole launch. An offline launch is
    // never the first one — signing in to the app needs the network — so the
    // anonymous session from that earlier launch is still on the device and
    // `currentUser` is already set; this branch is only ever skipped, not
    // needed, without a connection.
    if (FirebaseAuth.instance.currentUser == null) {
      try {
        await FirebaseAuth.instance
            .signInAnonymously()
            .timeout(const Duration(seconds: 8));
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

  // The OS job that delivers offline saves when the app is not reopened.
  // Only registers the callback; nothing is scheduled until a save is left
  // waiting.
  await BackgroundSyncService.init();

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
      // Every screen sits under the connection strip — see ConnectionBanner.
      builder: (context, child) =>
          ConnectionBanner(child: child ?? const SizedBox.shrink()),
      home: const SplashScreen(),
    );
  }
}

