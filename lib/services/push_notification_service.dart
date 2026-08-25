import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_constant.dart';

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'daily_reminder_service.dart';
import 'fcm_v1_service.dart';
import 'notification_router.dart';

/// Raises the tray notification for [message], if this device should see it.
///
/// [fromBackgroundIsolate] says whether the local notifications plugin still
/// has to be set up. It matters more than it looks: the plugin is a singleton
/// per isolate, and `initialize` overwrites its tap callback with whatever it
/// is handed — so calling it again on the main isolate replaces the handler
/// [PushNotificationService.init] installed with null, and every tap from
/// then on lands nowhere. A background message runs in its own isolate, which
/// has never been through `init`, so that one does have to initialize.
Future<void> _showNotificationIfAppropriate(
  RemoteMessage message, {
  required bool fromBackgroundIsolate,
}) async {
  final data = message.data;

  // An admin changed the reminder settings. There is nothing to show — the
  // payload *is* the change, and every device re-arms its own job from it.
  // Handled before anything else so it reaches a device whose owner is not
  // holding it: this runs in the headless isolate too.
  if (data['type'] == 'reminder_config') {
    await DailyReminderService.applyFromPush(data);
    return;
  }

  final title = data['title'];
  final body = data['body'];
  final senderPhone = data['senderPhone'];
  final senderName = data['senderName']?.toString().trim() ?? 'Someone';
  final replyToSenderName = data['replyToSenderName']?.toString().trim() ?? '';
  final mentionsStr = data['mentions']?.toString() ?? '';

  if (title == null || body == null) return;

  SharedPreferences prefs = await SharedPreferences.getInstance();
  String currentUserPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
  String currentUserName =
      prefs.getString(AppConstant.keyUserName)?.trim() ?? '';

  if (senderPhone == currentUserPhone) {
    // Do not show notification to the user who sent the message
    return;
  }

  // A new-version notice is only for a device that does not have it yet.
  // The admin's device works out who to send it to from what each device
  // last recorded at launch, which is one launch out of date the moment
  // somebody installs the update — so the build itself has the last word.
  if (data['type'] == 'app_update') {
    final double published =
        double.tryParse((data['version'] ?? '').toString().trim()) ?? 0;
    if (published <= AppConstant.appVersion) return;
  }

  String displayTitle = title;

  // Format currentUserName for mention checking (e.g. "Mohammad Mostafa" -> "MohammadMostafa")
  String formattedCurrentUserName = currentUserName.replaceAll(' ', '');

  if (mentionsStr.isNotEmpty) {
    List<String> mentions = mentionsStr.split(',');
    if (mentions.contains(formattedCurrentUserName)) {
      displayTitle = '$senderName mentioned you';
    }
  } else if (replyToSenderName.isNotEmpty) {
    if (replyToSenderName == currentUserName) {
      displayTitle = '$senderName replied to you';
    } else {
      displayTitle = '$senderName replied to $replyToSenderName';
    }
  }

  final FlutterLocalNotificationsPlugin localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (fromBackgroundIsolate) {
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);

    await localNotificationsPlugin.initialize(initSettings);
  }

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important notifications.',
    importance: Importance.high,
  );

  await localNotificationsPlugin.show(
    message.hashCode,
    displayTitle,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        icon: '@mipmap/ic_launcher',
        importance: Importance.high,
        priority: Priority.high,
      ),
    ),
    payload: jsonEncode(message.data),
  );
}

/// Top-level function to handle background messages
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  await _showNotificationIfAppropriate(message, fromBackgroundIsolate: true);
}

class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    print('FCM: Starting PushNotificationService initialization...');

    // 1. Initialize local notifications FIRST
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();
    const InitializationSettings initSettings =
        InitializationSettings(android: androidSettings, iOS: iosSettings);

    await _localNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          final data = jsonDecode(response.payload!);
          _handleNotificationClick(data);
        }
      },
    );

    // 2. Create Android channel FIRST (before requesting permission)
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'This channel is used for important notifications.',
      importance: Importance.high,
    );

    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    print('FCM: Local notifications initialized and channel created.');

    // 3. Setup Listeners
    //
    // The permission itself is deliberately NOT requested here. This runs from
    // main(), before runApp(), where no resumed Activity exists to host the
    // Android 13+ system dialog — the request would resolve to `denied`
    // without ever showing a popup. NotificationPermissionService asks once the
    // UI is up, driven from SplashController.
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('FCM: Foreground message received: ${message.messageId}');
      await _showNotificationIfAppropriate(message,
          fromBackgroundIsolate: false);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('FCM: Notification opened from background');
      _handleNotificationClick(message.data);
    });

    // Two ways a tap can have started this process, and both have to be
    // asked: the system tray notification FCM itself posted, and the local
    // one `_showNotificationIfAppropriate` posted from the background
    // handler. Neither can navigate yet — `runApp` has not been called — so
    // the router files them and the splash hands them back.
    final RemoteMessage? initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      print('FCM: Notification opened from terminated state');
      _handleNotificationClick(initialMessage.data);
    }

    final NotificationAppLaunchDetails? launch =
        await _localNotificationsPlugin.getNotificationAppLaunchDetails();
    final String? launchPayload = launch?.notificationResponse?.payload;
    if ((launch?.didNotificationLaunchApp ?? false) &&
        launchPayload != null &&
        launchPayload.isNotEmpty) {
      print('FCM: Local notification opened from terminated state');
      _handleNotificationClick(
          Map<String, dynamic>.from(jsonDecode(launchPayload) as Map));
    }

    // Subscribe to topics.
    //
    // Not awaited: this runs before runApp(), and FCM only completes a topic
    // subscription once the server has confirmed it — with no connection that
    // is never, and the app would sit on the native splash for as long as it
    // stayed offline. The SDK persists the request and retries by itself, so
    // nothing is lost by moving on.
    subscribeToGroupTopic();

    // Subscribe to personal topic based on phone number
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String userPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
    if (userPhone.isNotEmpty) {
      subscribeToUserTopic(userPhone);
    } else {
      print(
          'FCM: No phone number found in SharedPreferences, skipping personal topic subscription');
    }

    _isInitialized = true;
  }

  Future<void> subscribeToGroupTopic() async {
    try {
      await _fcm.subscribeToTopic('group_chat');
      print('FCM: Successfully subscribed to group_chat topic');
    } catch (e) {
      print('FCM: Error subscribing to group_chat topic: $e');
    }
  }

  Future<void> subscribeToUserTopic(String phone) async {
    if (phone.isEmpty) return;
    try {
      String safePhone = phone.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '');
      await _fcm.subscribeToTopic('user_$safePhone');
      print('FCM: Successfully subscribed to personal topic: user_$safePhone');
    } catch (e) {
      print('FCM: Error subscribing to personal topic: $e');
    }
  }

  /// Returns true when every topic accepted the message. False covers both
  /// "no network" and "FCM said no" — the caller that cares (the push outbox)
  /// retries either way, up to a point.
  Future<bool> sendPushNotification({
    required String title,
    required String body,
    List<String>? targetPhones,
    Map<String, dynamic>? data,

    /// Public URL of a picture to show inside the notification — a chat photo
    /// is worth seeing from the shade.
    String? imageUrl,

    /// Send the payload without a `notification` block, so the receiving
    /// device decides whether to raise it at all rather than the system tray
    /// showing it on arrival. What the new-version notice needs: only a
    /// device that is actually behind should see one.
    bool dataOnly = false,
  }) async {
    try {
      final String accessToken = await FcmV1Service().getAccessToken();
      if (accessToken.isEmpty) {
        print('Notification Error: Failed to get access token');
        return false;
      }

      print("access token : ----> ${accessToken}");

      const String projectId = 'home-expense-tracker-54c89';
      final url = Uri.parse(
          'https://fcm.googleapis.com/v1/projects/$projectId/messages:send');

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };

      final List<String> topics = [];
      if (targetPhones != null && targetPhones.isNotEmpty) {
        for (final phone in targetPhones) {
          String safePhone = phone.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '');
          topics.add('user_$safePhone');
        }
      } else {
        topics.add('group_chat');
      }

      print("topics : ----> ${topics.toString()}");

      bool allSent = true;
      for (final topic in topics) {
        final payload = {
          'message': {
            'topic': topic,
            if (!dataOnly)
              'notification': {
                'title': title,
                'body': body,
                if (imageUrl != null) 'image': imageUrl,
              },
            'data': {
              'title': title,
              'body': body,
              'click_action': 'FLUTTER_NOTIFICATION_CLICK',
              if (imageUrl != null) 'imageUrl': imageUrl,
              ...?data,
            },
            'android': {
              'priority': 'high',
              if (!dataOnly)
                'notification': {
                  'channel_id': 'high_importance_channel',
                  if (imageUrl != null) 'image': imageUrl,
                },
            },
            'apns': {
              'payload': {
                'aps': {
                  'content-available': 1,
                  'sound': 'default',
                  if (imageUrl != null) 'mutable-content': 1,
                }
              },
              'headers': {
                'apns-priority': '10',
              },
              if (imageUrl != null) 'fcm_options': {'image': imageUrl},
            }
          }
        };

        // Bounded: a link that is up but not answering must not hold a save.
        final response = await http
            .post(url, headers: headers, body: jsonEncode(payload))
            .timeout(const Duration(seconds: 20));
        if (response.statusCode != 200) {
          print('FCM Send Error [Topic: $topic]: ${response.body}');
          allSent = false;
        } else {
          print('FCM Send Success [Topic: $topic]');
        }
      }
      return allSent;
    } catch (e) {
      print('Error in sendPushNotification: $e');
      return false;
    }
  }

  /// Every tap goes to the same place — see [NotificationRouter], which owns
  /// the map from a notification's `type` to the screen it belongs to and
  /// knows what to do when the tap arrives before there is a navigator.
  void _handleNotificationClick(Map<String, dynamic> data) =>
      NotificationRouter().handle(data);
}
