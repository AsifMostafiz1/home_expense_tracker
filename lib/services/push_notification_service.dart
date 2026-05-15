import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_constant.dart';

import 'dart:convert';
import 'package:get/get.dart';
import '../presentation/dashboard/view/dashboard_screen.dart';

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
  String currentUserName = prefs.getString(AppConstant.keyUserName)?.trim() ?? '';

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

  final FlutterLocalNotificationsPlugin localNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
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
  static final PushNotificationService _instance = PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    // Request permissions (required for iOS and Android 13+)
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );

    // Initialize local notifications for foreground display
    const AndroidInitializationSettings androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
    
    await _localNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null) {
          final data = jsonDecode(response.payload!);
          _handleNotificationClick(data);
        }
      },
    );

    // Create Android channel
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel',
      'High Importance Notifications',
      description: 'This channel is used for important notifications.',
      importance: Importance.high,
    );

    await _localNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Handle background messages
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      await _showNotificationIfAppropriate(message);
    });

    // Handle app opening from notification (background state)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationClick(message.data);
    });

    // Handle app opening from notification (terminated state)
    RemoteMessage? initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationClick(initialMessage.data);
    }

    // Subscribe to group chat topic
    await _fcm.subscribeToTopic('group_chat');

    _isInitialized = true;
  }

  void _handleNotificationClick(Map<String, dynamic> data) {
    if (data['type'] == 'chat_message') {
      Get.offAll(() => const DashboardScreen(initialIndex: 2));
    }
  }
}
