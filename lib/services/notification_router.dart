import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../common/binding/initial_binding.dart';
import '../presentation/chat/controller/chat_controller.dart';
import '../presentation/chat/model/chat_thread_model.dart';
import '../presentation/chat/repository/chat_repository.dart';
import '../presentation/chat/view/chat_screen.dart';
import '../presentation/dashboard/view/dashboard_screen.dart';
import '../presentation/house_rules/view/house_rules_screen.dart';
import '../presentation/house_rules/widgets/house_rules_gate.dart';
import '../presentation/monthly_stats/controller/monthly_stats_controller.dart';
import '../presentation/monthly_stats/view/monthly_stats_screen.dart';
import '../presentation/splash/view/splash_screen.dart';
import '../utils/app_constant.dart';
import 'home_refresh.dart';

/// Where a tapped notification lands.
///
/// One per `type` the app sends. The tab is what shows underneath; a few of
/// them also open a screen on top, because the notification was about one
/// particular thing rather than a section of the app.
enum NotificationDestination {
  /// The meal screen — the announcement card and the meal figures both live
  /// there.
  meals(tab: 0),

  expenses(tab: 1),

  /// A group message: the chat tab, with the house thread opened on it.
  groupThread(tab: 2),

  /// A direct message: the chat tab, with that person's thread opened on it.
  directThread(tab: 2),

  /// The rules, reached from the profile the way they are in the menu.
  houseRules(tab: 4),

  monthlyBill(tab: 4),

  /// A role change — the badge and the menu that goes with it.
  profile(tab: 4),

  /// The account is gone. Nothing to open: back through the splash, which
  /// re-reads the record and ends the session with a reason.
  signedOut(tab: -1),

  /// A new build to install. Nothing inside the app answers this — the tap
  /// goes to wherever the build is hosted.
  appUpdate(tab: -1);

  const NotificationDestination({required this.tab});

  /// Index into the dashboard's tabs, or -1 for a destination that is not a
  /// tab at all.
  final int tab;
}

/// What every notification the app sends does when it is tapped.
///
/// A tap that lands on the home screen and leaves the reader to go looking is
/// a tap that wasted their time, so each `type` has a destination and the ones
/// that are about a single thing open it.
///
/// Taps arrive in three different states, which is the whole reason this is a
/// service rather than a switch statement:
///
///   • **App in front.** The home screen is up; move to the right tab and put
///     whatever belongs on top of it.
///   • **App in the background.** The same, once the tap wakes it.
///   • **App not running.** The tap is read in `main()`, before `runApp()` —
///     there is no navigator yet, so routing then would do nothing at all. It
///     is filed instead, and the splash hands it back through [onAppReady]
///     once the version gate and the account check have let the app through.
class NotificationRouter {
  static final NotificationRouter _instance = NotificationRouter._();
  factory NotificationRouter() => _instance;
  NotificationRouter._();

  /// A tap that arrived before there was anywhere to send it.
  Map<String, dynamic>? _pending;

  /// How long a route change needs before the next one can be stacked on it.
  /// GetX's default transition runs 300ms.
  static const Duration _settle = Duration(milliseconds: 320);

  /// The `type` on a notification's payload, mapped to where it goes.
  ///
  /// Every sender in the app is listed here. An unknown one — an older
  /// build's notification, or one this version does not know about — opens
  /// the app rather than doing nothing.
  static NotificationDestination destinationFor(String? type) {
    switch (type) {
      case 'chat_message':
        return NotificationDestination.groupThread;
      case 'direct_message':
        return NotificationDestination.directThread;
      case 'announcement':
      case 'meal':
        return NotificationDestination.meals;
      case 'expense':
        return NotificationDestination.expenses;
      case 'house_rules':
        return NotificationDestination.houseRules;
      case 'monthly_bill':
        return NotificationDestination.monthlyBill;
      case 'role':
        return NotificationDestination.profile;
      case 'account_removed':
        return NotificationDestination.signedOut;
      case 'app_update':
        return NotificationDestination.appUpdate;
      default:
        return NotificationDestination.meals;
    }
  }

  /// A notification was tapped.
  ///
  /// Routes straight away when the home screen is up, and files the tap
  /// otherwise — the splash is still running, or the app is still starting.
  void handle(Map<String, dynamic> data) {
    _pending = data;
    if (DashboardScreen.isOpen) _drain();
  }

  /// The splash has finished and the home screen is up. Anything filed while
  /// the app was starting goes now.
  Future<void> onAppReady() async {
    if (_pending == null) return;
    // The home screen was pushed a moment ago; wait for its first frame so
    // the route below is switched rather than rebuilt.
    await Future.delayed(_settle);
    await _drain();
  }

  Future<void> _drain() async {
    final Map<String, dynamic>? data = _pending;
    if (data == null) return;
    _pending = null;

    try {
      // Agreeing to a house rule is the one thing a notification does not get
      // to interrupt: that screen is mandatory and an ordinary route, so the
      // tab switch below would pop it. Wait it out, and drop the tap if the
      // member is still reading — whatever it was about keeps its unread mark
      // either way.
      if (!await _waitForRulesGate()) return;
      await _route(data);
    } catch (e) {
      // A tap that cannot be routed must still leave the app usable.
      debugPrint('NotificationRouter: could not open ${data['type']} — $e');
    }
  }

  /// True once nothing mandatory is in front of the user. False if something
  /// still is after the wait, in which case the tap is dropped rather than
  /// dismissing it.
  Future<bool> _waitForRulesGate() async {
    for (int i = 0; i < 180; i++) {
      if (!HouseRulesGate.isShowing) return true;
      await Future.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<void> _route(Map<String, dynamic> data) async {
    final NotificationDestination destination =
        destinationFor(data['type']?.toString());

    if (destination == NotificationDestination.signedOut) {
      Get.offAll(() => const SplashScreen());
      return;
    }

    // Straight to the download rather than into the app: the whole point of
    // the notice is the file, and the splash gate is what decides whether
    // this build may still be used in the meantime.
    if (destination == NotificationDestination.appUpdate) {
      await _openDownloadLink(data);
      return;
    }

    // Nothing opens for somebody who is not signed in — the notification
    // outlived the session it belonged to.
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(AppConstant.keyIsLoggedIn) ?? false)) return;

    await _openTab(destination.tab);

    // The tab is showing; bring what is on it up to date underneath. Not
    // awaited — see [_refreshFor].
    unawaited(_refreshFor(destination));

    switch (destination) {
      case NotificationDestination.directThread:
        await _openDirectThread(data, prefs);
        break;

      case NotificationDestination.groupThread:
        // Into the thread itself, not the list of them: the tap was on a
        // message. Back from here lands on the list.
        await _push(() => const ChatScreen());
        break;

      case NotificationDestination.houseRules:
        // The home screen raises the acknowledgement gate by itself when a
        // rule is unagreed, and that lands on top of this. Somebody who has
        // already agreed still gets to see what changed.
        await _push(() => const HouseRulesScreen());
        break;

      case NotificationDestination.monthlyBill:
        // Read here rather than in [_refreshFor], because the per-month
        // figures have to be switched on before the read rather than after it
        // — see MonthlyStatsController.reload. The launch only worked out the
        // current month, and none of the bills are live.
        if (Get.isRegistered<MonthlyStatsController>() &&
            !Get.isPrepared<MonthlyStatsController>()) {
          unawaited(
            Get.find<MonthlyStatsController>().reload(withHistory: true),
          );
        }
        await _push(() => const MonthlyStatsScreen());
        break;

      // The tab is the whole destination.
      case NotificationDestination.meals:
      case NotificationDestination.expenses:
      case NotificationDestination.profile:
      case NotificationDestination.signedOut:
      case NotificationDestination.appUpdate:
        break;
    }
  }

  /// Brings the data behind [destination] up to date.
  ///
  /// Which of them need it, and what refreshing one means, is [HomeRefresh] —
  /// the same reads coming back to a backgrounded app runs. This only decides
  /// which destinations are worth it: the chat and the house rules are live,
  /// and the month's bills are read where that screen is opened, because the
  /// per-month figures have to be switched on before the read rather than
  /// after it.
  ///
  /// Not awaited by the caller: the tap belongs on the screen straight away,
  /// and these are reads that take a moment on a poor connection.
  Future<void> _refreshFor(NotificationDestination destination) async {
    switch (destination) {
      case NotificationDestination.meals:
      case NotificationDestination.expenses:
      case NotificationDestination.profile:
        await HomeRefresh.tab(destination.tab);
        break;

      // Live already, read where the screen is opened, or not a screen.
      case NotificationDestination.groupThread:
      case NotificationDestination.directThread:
      case NotificationDestination.houseRules:
      case NotificationDestination.monthlyBill:
      case NotificationDestination.signedOut:
      case NotificationDestination.appUpdate:
        break;
    }
  }

  /// Opens wherever the new build is hosted, in the browser.
  ///
  /// A notice with no link — or one saved wrong — leaves the app where it
  /// was rather than throwing the reader out of it; the update screen the
  /// next launch raises carries the same link and can be retried there.
  Future<void> _openDownloadLink(Map<String, dynamic> data) async {
    final String link = (data['downloadLink'] ?? '').toString().trim();
    final Uri? uri = link.isEmpty ? null : Uri.tryParse(link);
    if (uri == null || !uri.isAbsolute) return;
    if (uri.scheme != 'http' && uri.scheme != 'https') return;

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('NotificationRouter: could not open $link — $e');
    }
  }

  /// Brings the home screen forward on [index].
  ///
  /// Whatever the reader had stacked on top of it belongs to what they were
  /// doing before, not to this notification, so it is cleared first.
  Future<void> _openTab(int index) async {
    if (DashboardScreen.isOpen) {
      if (Get.key.currentState?.canPop() ?? false) {
        Get.until((route) => route.isFirst);
      }
      DashboardScreen.selectTab(index);
    } else {
      // Only reached if a tap is routed with no home screen up — the filing
      // in [handle] normally keeps that from happening.
      Get.offAll(
        () => DashboardScreen(initialIndex: index),
        binding: InitialBinding(),
      );
    }
    await Future.delayed(_settle);
  }

  Future<void> _push(Widget Function() page) async {
    if (Get.key.currentState == null) return;
    Get.to(page);
    await Future.delayed(_settle);
  }

  /// Opens the direct chat with whoever sent the notification.
  ///
  /// The sender is the peer, seen from this device. Everything the header
  /// needs rides on the payload, so the screen can be drawn before anything
  /// is read back.
  Future<void> _openDirectThread(
    Map<String, dynamic> data,
    SharedPreferences prefs,
  ) async {
    final String peerPhone = (data['senderPhone'] ?? '').toString();
    if (peerPhone.isEmpty) return;

    final String myPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
    if (myPhone.isEmpty || myPhone == peerPhone) return;
    if (!Get.isRegistered<ChatRepository>()) return;

    final String image = (data['senderImage'] ?? '').toString();
    final ChatThread thread = ChatThread.direct(
      peerPhone: peerPhone,
      peerName: (data['senderName'] ?? '').toString(),
      peerImage: image.isEmpty ? null : image,
      myPhone: myPhone,
    );
    final String tag = thread.controllerTag!;

    if (!Get.isRegistered<ChatController>(tag: tag)) {
      Get.put(
        ChatController(repository: Get.find<ChatRepository>(), thread: thread),
        tag: tag,
      );
    }
    await _push(() => ChatScreen(tag: tag));
  }
}
