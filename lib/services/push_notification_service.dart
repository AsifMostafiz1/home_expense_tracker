import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../utils/app_constant.dart';

import 'dart:convert';
import 'package:get/get.dart';
import '../presentation/dashboard/view/dashboard_screen.dart';
import 'package:http/http.dart' as http;
import 'fcm_v1_service.dart';
import '../common/binding/initial_binding.dart';

Future<void> _showNotificationIfAppropriate(RemoteMessage message) async {
  final data = message.data;
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

  // Initialize for the current instance (important for background/separate isolate)
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const DarwinInitializationSettings iosSettings =
      DarwinInitializationSettings();
  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings, iOS: iosSettings);

  await localNotificationsPlugin.initialize(initSettings);

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
  await _showNotificationIfAppropriate(message);
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

    // 3. Request permissions using permission_handler (More reliable for Android 13+)
    if (Platform.isAndroid) {
      print('FCM: Requesting Android permission via permission_handler...');
      PermissionStatus status = await Permission.notification.status;
      print('FCM: Initial permission status: $status');

      if (status.isDenied || status.isRestricted) {
        status = await Permission.notification.request();
        print('FCM: Permission requested, new status: $status');
      }

      if (status.isPermanentlyDenied || status.isDenied) {
        print('FCM: Permission blocked or denied. Opening app settings...');
        await openAppSettings();
      }
    }

    // 4. Also call FCM requestPermission (especially for iOS)
    print('FCM: Requesting permissions via Firebase Messaging...');
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    print(
        'FCM: Firebase Messaging authorizationStatus: ${settings.authorizationStatus}');

    // 5. Setup Listeners
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('FCM: Foreground message received: ${message.messageId}');
      await _showNotificationIfAppropriate(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('FCM: Notification opened from background');
      _handleNotificationClick(message.data);
    });

    RemoteMessage? initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      print('FCM: Notification opened from terminated state');
      _handleNotificationClick(initialMessage.data);
    }

    // Subscribe to topics
    await subscribeToGroupTopic();

    // Subscribe to personal topic based on phone number
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String userPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
    if (userPhone.isNotEmpty) {
      await subscribeToUserTopic(userPhone);
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

  Future<void> sendPushNotification({
    required String title,
    required String body,
    List<String>? targetPhones,
    Map<String, dynamic>? data,
  }) async {
    try {
      final String accessToken = await FcmV1Service().getAccessToken();
      if (accessToken.isEmpty) {
        print('Notification Error: Failed to get access token');
        return;
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

      for (final topic in topics) {
        final payload = {
          'message': {
            'topic': topic,
            'notification': {
              'title': title,
              'body': body,
            },
            'data': {
              'title': title,
              'body': body,
              'click_action': 'FLUTTER_NOTIFICATION_CLICK',
              ...?data,
            },
            'android': {
              'priority': 'high',
              'notification': {
                'channel_id': 'high_importance_channel',
              }
            },
            'apns': {
              'payload': {
                'aps': {
                  'content-available': 1,
                  'sound': 'default',
                }
              },
              'headers': {
                'apns-priority': '10',
              }
            }
          }
        };

        final response =
            await http.post(url, headers: headers, body: jsonEncode(payload));
        if (response.statusCode != 200) {
          print('FCM Send Error [Topic: $topic]: ${response.body}');
        } else {
          print('FCM Send Success [Topic: $topic]');
        }
      }
    } catch (e) {
      print('Error in sendPushNotification: $e');
    }
  }

  void _handleNotificationClick(Map<String, dynamic> data) {
    if (data['type'] == 'chat_message' || data['type'] == 'announcement') {
      Get.offAll(() => const DashboardScreen(initialIndex: 2),
          binding: InitialBinding());
    }
  }
}
