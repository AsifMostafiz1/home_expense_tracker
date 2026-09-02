import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Color;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../presentation/settings/model/app_config_model.dart';
import '../utils/app_constant.dart';

/// The house's daily meal reminder.
///
/// An admin decides two things from the settings screen — whether it goes out
/// at all, and at what hour — and both live on `config/business_config`
/// alongside the version gate. Every device then raises the reminder for
/// itself at that hour, so no server is involved in the sending.
///
/// **Why a background job rather than a scheduled notification.** The text is
/// not fixed: it names who is eating today and who is not, and those rows keep
/// changing right up to the evening. A notification handed to the OS in
/// advance would carry whatever was true when it was scheduled — this morning,
/// or yesterday. So the OS is asked to *wake the app* at the hour instead, and
/// the summary is read then, moments before it is shown. The cost is
/// precision: WorkManager may run the job a little after the hour, where an
/// alarm would have been exact. Fresh names are worth more than an exact
/// minute, and [_staleAfter] draws the line past which a very late wake-up
/// says nothing rather than something wrong.
///
/// Each device fires on its own clock, so the hour is local to whoever is
/// reading it. For a house that lives together that is the same moment.
class DailyReminderService {
  DailyReminderService._();

  /// One job at a time, under one name. On iOS this is also the
  /// `BGTaskSchedulerPermittedIdentifiers` entry in Info.plist.
  static const String uniqueName =
      'com.mostafizur.expense.tracker.daily_reminder';
  static const String taskName = 'dailyMealReminder';

  /// Fixed, so a reminder that somehow runs twice replaces the first one in
  /// the shade instead of stacking beside it.
  static const int _notificationId = 20250;

  /// Its own channel rather than the one chat and announcements share: a
  /// nightly reminder is the notification somebody is most likely to want
  /// silenced on its own, and Android only offers that per channel.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'daily_reminder_channel',
    'Daily meal reminder',
    description: 'The evening summary of who is eating today.',
    importance: Importance.high,
  );

  /// How late a wake-up may be and still be worth showing. Past this the
  /// evening has moved on and "today's meals" is no longer news — the job
  /// re-arms for tomorrow and says nothing.
  static const Duration _staleAfter = Duration(hours: 3);

  static const Duration _readTimeout = Duration(seconds: 12);

  /// Brings this device's job in line with [config].
  ///
  /// Cheap and idempotent — called on every launch, and again whenever an
  /// admin's change arrives. A null [config] means the read failed, in which
  /// case the last settings this device saw stand.
  /// Returns false when the OS refused the job — the settings are saved, but
  /// nothing will come of them until it is asked again.
  static Future<bool> sync(AppConfigModel? config) async {
    // The reminder rides on WorkManager and local notifications, and the web
    // has neither — a tab cannot be woken at dinner time. The settings are
    // still cached so a phone signing in later starts from the right ones.
    if (kIsWeb) {
      if (config != null) {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        await _cache(prefs, config.reminderEnabled, config.reminderTime);
      }
      return true;
    }

    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // Nothing to remind someone who is not signed in — the house's meals are
    // not theirs to see. [run] checks this again at the hour, in case the
    // session ends between now and then. A general user is signed in but
    // eats none of those meals, so their evening is left alone too.
    if (!(prefs.getBool(AppConstant.keyIsLoggedIn) ?? false) ||
        _isGeneralUser(prefs)) {
      await cancel();
      return true;
    }

    if (config != null) {
      await _cache(prefs, config.reminderEnabled, config.reminderTime);
      return _arm(config.reminderEnabled, config.reminderTime);
    }

    final (bool enabled, String time) = _cached(prefs);
    return _arm(enabled, time);
  }

  /// An admin changed the settings a moment ago and the change arrived as a
  /// silent message. Same as [sync], from the two strings a push payload can
  /// carry.
  ///
  /// Runs in whichever isolate took the message — including the headless one
  /// Firebase wakes for a backgrounded app, which is the point: the new hour
  /// reaches a device that nobody is holding.
  static Future<void> applyFromPush(Map<String, dynamic> data) async {
    final bool enabled = data['enabled']?.toString() == '1';
    final String time =
        AppConfigModel.normalizeTime(data['time']?.toString() ?? '');

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await _cache(prefs, enabled, time);

    if (kIsWeb) return;
    if (!(prefs.getBool(AppConstant.keyIsLoggedIn) ?? false)) return;
    if (_isGeneralUser(prefs)) return;
    await _arm(enabled, time);
  }

  /// Whether this device belongs to a general user — no meals, no reminder.
  static bool _isGeneralUser(SharedPreferences prefs) =>
      prefs.getString(AppConstant.keyUserType) == AppConstant.userTypeGeneral;

  /// The master notification switch, as well as this isolate can know it.
  ///
  /// The live config wins. With none — the read failed — Firestore's own
  /// local copy of the document is asked first: it has read-your-writes, so
  /// an admin who flipped the switch and then lost the network is honoured
  /// tonight, not at their next launch. The launch-cached JSON stands in
  /// after that; with nothing at all, the switch reads as on, the same
  /// default the send-time gate falls back to.
  static Future<bool> _masterEnabled(
    SharedPreferences prefs,
    AppConfigModel? config,
  ) async {
    if (config != null) return config.notificationsEnabled;

    try {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await FirebaseFirestore.instance
              .collection(AppConstant.collectionConfig)
              .doc(AppConstant.docBusinessConfig)
              .get(const GetOptions(source: Source.cache))
              .timeout(const Duration(seconds: 5));
      final Map<String, dynamic>? data = doc.data();
      if (data != null) {
        return data[AppConstant.fieldNotificationsEnabled] != false;
      }
    } catch (_) {
      // No local copy of the document; the launch-cached JSON is next.
    }

    try {
      final String? raw = prefs.getString(AppConstant.keyCachedAppConfig);
      if (raw == null || raw.isEmpty) return true;
      final dynamic cached = jsonDecode(raw);
      if (cached is Map) {
        return cached[AppConstant.fieldNotificationsEnabled] != false;
      }
    } catch (_) {}
    return true;
  }

  /// Stops the reminder on this device. Signing out, and an admin switching it
  /// off for the house, both land here.
  static Future<void> cancel() async {
    if (kIsWeb) return;
    try {
      await Workmanager().cancelByUniqueName(uniqueName);
      debugPrint('DailyReminder: job cancelled');
    } catch (e) {
      debugPrint('DailyReminder: cancel failed — $e');
    }
  }

  /// Asks the OS to wake the app at the next [time].
  ///
  /// [from] is the moment "next" is counted from, and only the job re-arming
  /// itself passes one — see the call at the end of [run].
  static Future<bool> _arm(bool enabled, String time, {DateTime? from}) async {
    if (!enabled) {
      await cancel();
      return true;
    }

    final DateTime next = nextOccurrence(
      AppConfigModel.hourOf(time),
      AppConfigModel.minuteOf(time),
      from: from,
    );
    final Duration delay = next.difference(DateTime.now());

    try {
      if (Platform.isIOS) {
        // iOS has no equivalent of an initial delay: a BGProcessingTask runs
        // when the system decides the moment is right. The reminder is
        // therefore best-effort there, and [run] drops one that arrives far
        // from the hour it was meant for.
        await Workmanager().registerProcessingTask(uniqueName, taskName);
      } else {
        await Workmanager().registerOneOffTask(
          uniqueName,
          taskName,
          initialDelay: delay,
          // Deliberately no network constraint: the reminder should appear at
          // the hour even with the connection down, reading what Firestore
          // has cached rather than waiting for one.
          existingWorkPolicy: ExistingWorkPolicy.replace,
        );
      }
      debugPrint('DailyReminder: armed for $next (in ${delay.inMinutes} min)');
      return true;
    } catch (e) {
      // Worth surfacing rather than only logging: an admin who saved a time
      // and was told nothing would wait all evening for a reminder that was
      // never asked for. [sync] hands this back to the settings screen.
      debugPrint('DailyReminder: could not arm — $e');
      return false;
    }
  }

  /// The next time the clock reads [hour]:[minute] — today if that is still
  /// ahead, tomorrow otherwise.
  ///
  /// Built through the local-time constructor rather than by adding 24 hours,
  /// so a day that is not 24 hours long still lands on the right hour.
  static DateTime nextOccurrence(int hour, int minute, {DateTime? from}) {
    final DateTime now = from ?? DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day, hour, minute);
    if (today.isAfter(now)) return today;
    return DateTime(now.year, now.month, now.day + 1, hour, minute);
  }

  /// The job itself. Runs in the headless isolate the OS wakes — no GetX, no
  /// translations, no widgets — so everything it needs is built right here.
  ///
  /// Always returns true. A reminder that could not be assembled is a reminder
  /// that has missed its moment; asking the OS to retry it an hour later would
  /// only deliver the wrong evening's news.
  static Future<bool> run() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      // Already initialised in this isolate, or genuinely broken. The reads
      // below will say which.
      debugPrint('DailyReminder: Firebase init — $e');
    }

    try {
      FirebaseFirestore.instance.settings =
          const Settings(persistenceEnabled: true);
    } catch (_) {}

    final SharedPreferences prefs = await SharedPreferences.getInstance();

    // The session may have ended since the job was armed — or the account
    // may have become a general user's, whose meals are nobody's to count.
    if (!(prefs.getBool(AppConstant.keyIsLoggedIn) ?? false) ||
        _isGeneralUser(prefs)) {
      await cancel();
      return true;
    }

    // Live settings if they can be had, and what this device last saw if not.
    // An admin who switched the reminder off while this device was offline is
    // honoured the moment it can be read.
    final AppConfigModel? config = await _readConfig();
    final (bool cachedEnabled, String cachedTime) = _cached(prefs);
    final bool enabled = config?.reminderEnabled ?? cachedEnabled;
    final String time = config?.reminderTime ?? cachedTime;

    if (config != null) {
      await _cache(prefs, config.reminderEnabled, config.reminderTime);
    }

    if (!enabled) {
      await cancel();
      return true;
    }

    // The house's master notification switch — the same one every push obeys
    // at send time. Skipped rather than cancelled: the schedule survives, so
    // the evening the switch comes back on needs no re-arming from anywhere.
    if (!await _masterEnabled(prefs, config)) {
      debugPrint('DailyReminder: master notification switch is off — skipped');
    } else if (isOnTime(time)) {
      try {
        await _notify(prefs, fromBackgroundIsolate: true);
      } catch (e) {
        debugPrint('DailyReminder: could not raise the reminder — $e');
      }
    } else {
      debugPrint('DailyReminder: woke too late for $time — skipped');
    }

    // Last, and after the notification is already in the shade: re-arming
    // under the same unique name replaces the work this very job is running
    // as, which can cut it short. Nothing below here would have run anyway.
    //
    // Counted from the hour itself rather than from now, so a job the OS ran
    // a few minutes early is not simply armed for later the same evening and
    // shown twice.
    final DateTime now = DateTime.now();
    final DateTime target = DateTime(
      now.year,
      now.month,
      now.day,
      AppConfigModel.hourOf(time),
      AppConfigModel.minuteOf(time),
    );
    await _arm(enabled, time, from: now.isAfter(target) ? now : target);
    return true;
  }

  /// Raises tonight's reminder right now, whatever the clock says.
  ///
  /// What an admin presses to see the thing itself rather than wait until the
  /// evening to find out. It reads the same rows and writes the same sentence
  /// the real one will; nothing about the schedule is touched.
  ///
  /// Returns what the notification says, so the screen can show it to an admin
  /// whose notifications turn out to be switched off at the OS level — the one
  /// failure this cannot see for itself.
  static Future<String> showNow() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return _notify(prefs, fromBackgroundIsolate: false);
  }

  /// True when the wake-up is close enough to the hour it was meant for.
  ///
  /// [at] stands in for the clock, so this can be asked about a moment other
  /// than now.
  static bool isOnTime(String time, {DateTime? at}) {
    final DateTime now = at ?? DateTime.now();
    final DateTime target = DateTime(
      now.year,
      now.month,
      now.day,
      AppConfigModel.hourOf(time),
      AppConfigModel.minuteOf(time),
    );

    // A job may be woken a shade early as easily as late; both count.
    if (now.isBefore(target)) {
      return target.difference(now) <= const Duration(minutes: 15);
    }
    return now.difference(target) <= _staleAfter;
  }

  /// ------------------------------------------------------------- the message

  /// Raises the reminder for tonight.
  ///
  /// [fromBackgroundIsolate] carries the same weight it does in
  /// `PushNotificationService`: the local notifications plugin is a singleton
  /// per isolate and `initialize` overwrites its tap callback with whatever it
  /// is handed. Calling it again on the main isolate would replace the handler
  /// `PushNotificationService.init` installed with null, and every tap on
  /// every notification from then on would land nowhere. The headless isolate
  /// has never been through that setup, so that one does have to initialize.
  static Future<String> _notify(
    SharedPreferences prefs, {
    required bool fromBackgroundIsolate,
  }) async {
    final DailyMealSummary summary = await _todaysMeals();
    final bool bengali =
        (prefs.getString(AppConstant.keyLanguage) ?? 'en') == 'bn';

    final String title = bengali ? 'আজকের মিল' : "Today's meals";
    final String body = summary.describe(bengali: bengali);

    // No local notifications on web — but the sentence is still worth
    // returning: the settings screen's "show now" displays it itself.
    if (kIsWeb) return body;

    final FlutterLocalNotificationsPlugin plugin =
        FlutterLocalNotificationsPlugin();

    if (fromBackgroundIsolate) {
      // No tap callback is passed: the isolate is gone by the time anyone
      // taps, and the launch details the next start reads carry the payload
      // instead.
      await plugin.initialize(const InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: DarwinInitializationSettings(),
      ));
    }

    // Creating a channel that exists is a no-op, and this may be the first
    // time this build has raised one on this channel.
    await plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    await plugin.show(
      _notificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          icon: '@drawable/ic_notification',
          color: const Color(AppConstant.notificationAccent),
          importance: Importance.high,
          priority: Priority.high,
          // The names are the message, and a shade line is not long enough to
          // hold them — this lets the reader pull it open.
          styleInformation: BigTextStyleInformation(body, contentTitle: title),
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(const {'type': 'meal_reminder'}),
    );
    debugPrint('DailyReminder: shown — $body');
    return body;
  }

  /// Who is eating today, and who is not.
  ///
  /// Both halves matter: a house wants to know the count to cook to, and a
  /// member who forgot to put their meal in wants to be told before dinner is
  /// made without them.
  static Future<DailyMealSummary> _todaysMeals() async {
    final DateTime now = DateTime.now();
    final String today = _dayKey(now);
    final String tomorrow = _dayKey(DateTime(now.year, now.month, now.day + 1));

    // `date_time` is an ISO-8601 string, so a day is everything sorting
    // between its own date and the next one — the same way the monthly
    // figures are read.
    final QuerySnapshot<Map<String, dynamic>>? mealSnap = await _read(
      FirebaseFirestore.instance
          .collection(AppConstant.collectionMeals)
          .where('date_time', isGreaterThanOrEqualTo: today)
          .where('date_time', isLessThan: tomorrow),
    );

    final QuerySnapshot<Map<String, dynamic>>? userSnap = await _read(
      FirebaseFirestore.instance.collection(AppConstant.collectionUsers),
    );

    final Map<String, int> countByPhone = {};
    final Map<String, String> nameByPhone = {};

    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in mealSnap?.docs ?? const []) {
      final Map<String, dynamic> data = doc.data();
      final String phone = (data['user_phone'] ?? '').toString();
      if (phone.isEmpty) continue;

      // A day can hold more than one row per person only if something went
      // wrong upstream, but summing is the reading that is never surprising.
      countByPhone[phone] =
          (countByPhone[phone] ?? 0) + ((data['meal_count'] ?? 0) as num).toInt();
      nameByPhone[phone] = (data['user_name'] ?? '').toString();
    }

    final List<MealShare> eating = [];
    final List<String> skipping = [];

    // Driven by the member list rather than the meal rows, because the people
    // with no meal today have no row to be found in. Removed accounts stay in
    // Firestore as tombstones and are not part of the house any more.
    for (final QueryDocumentSnapshot<Map<String, dynamic>> doc
        in userSnap?.docs ?? const []) {
      final Map<String, dynamic> data = doc.data();
      if (data['removed'] == true) continue;
      // A general user is not part of the meal programme; without this they
      // would stand in "skipping" every evening forever.
      if (data['userType'] == AppConstant.userTypeGeneral) continue;

      final String phone = doc.id;
      final String name = (data['name'] ?? '').toString().trim().isNotEmpty
          ? (data['name'] as String).trim()
          : (nameByPhone[phone] ?? '').trim();
      if (name.isEmpty) continue;

      final int count = countByPhone.remove(phone) ?? 0;
      if (count > 0) {
        eating.add(MealShare(name, count));
      } else {
        skipping.add(name);
      }
    }

    // Whoever the member list could not account for — it failed to read, or a
    // meal is filed against an account no longer listed. Their meals still
    // have to be cooked.
    countByPhone.forEach((String phone, int count) {
      final String name = (nameByPhone[phone] ?? '').trim();
      if (count > 0 && name.isNotEmpty) eating.add(MealShare(name, count));
    });

    eating.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    skipping.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return DailyMealSummary(eating: eating, skipping: skipping);
  }

  /// The server's answer, or the cached one when there is no connection —
  /// never an exception, because the reminder is worth showing either way.
  static Future<QuerySnapshot<Map<String, dynamic>>?> _read(
    Query<Map<String, dynamic>> query,
  ) async {
    try {
      return await query
          .get(const GetOptions(source: Source.server))
          .timeout(_readTimeout);
    } catch (e) {
      debugPrint('DailyReminder: live read failed ($e) — trying the cache');
      try {
        return await query.get(const GetOptions(source: Source.cache));
      } catch (e) {
        debugPrint('DailyReminder: cached read failed — $e');
        return null;
      }
    }
  }

  static String _dayKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// ------------------------------------------------------------ the settings

  static Future<AppConfigModel?> _readConfig() async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> snapshot =
          await FirebaseFirestore.instance
              .collection(AppConstant.collectionConfig)
              .doc(AppConstant.docBusinessConfig)
              .get(const GetOptions(source: Source.server))
              .timeout(_readTimeout);
      if (!snapshot.exists) return null;
      return AppConfigModel.fromMap(snapshot.data() ?? {});
    } catch (e) {
      debugPrint('DailyReminder: settings unreadable — $e');
      return null;
    }
  }

  static Future<void> _cache(
    SharedPreferences prefs,
    bool enabled,
    String time,
  ) async {
    try {
      await prefs.setString(
        AppConstant.keyReminderConfig,
        jsonEncode({'enabled': enabled, 'time': time}),
      );
    } catch (e) {
      debugPrint('DailyReminder: could not cache the settings — $e');
    }
  }

  static (bool, String) _cached(SharedPreferences prefs) {
    try {
      final String? raw = prefs.getString(AppConstant.keyReminderConfig);
      if (raw == null || raw.isEmpty) {
        return (false, AppConfigModel.defaultReminderTime);
      }
      final Map<String, dynamic> data =
          Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return (
        data['enabled'] == true,
        AppConfigModel.normalizeTime(data['time']),
      );
    } catch (e) {
      debugPrint('DailyReminder: cached settings unreadable — $e');
      return (false, AppConfigModel.defaultReminderTime);
    }
  }
}

/// One member's share of today — their name as the reminder will print it,
/// and how many meals they are down for.
class MealShare {
  final String name;
  final int count;

  const MealShare(this.name, this.count);
}

/// Today's meals, in the one sentence a notification has room for.
class DailyMealSummary {
  final List<MealShare> eating;
  final List<String> skipping;

  const DailyMealSummary({required this.eating, required this.skipping});

  int get total => eating.fold(0, (int sum, MealShare m) => sum + m.count);

  /// Written out here rather than through GetX translations: this is built in
  /// a headless isolate, where no `GetMaterialApp` has ever been created and
  /// `.tr` would hand back the key itself.
  String describe({required bool bengali}) {
    if (total == 0) {
      return bengali ? 'আজ কারও মিল নেই।' : 'No one has a meal today.';
    }

    // "Rahim 2" rather than "Rahim (2)" — parentheses read as an aside, and
    // the count is the point.
    final String who =
        eating.map((MealShare m) => '${m.name} ${m.count}').join(', ');

    final StringBuffer buffer = StringBuffer();
    if (bengali) {
      buffer.write('আজ $totalটি মিল — $who।');
    } else {
      buffer.write('$total ${total == 1 ? 'meal' : 'meals'} today — $who.');
    }

    if (skipping.isNotEmpty) {
      buffer.write(bengali
          ? ' মিল নেই: ${skipping.join(', ')}।'
          : ' No meal: ${skipping.join(', ')}.');
    }
    return buffer.toString();
  }
}
