import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_constant.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'daily_reminder_service.dart';
import 'fcm_v1_service.dart';
import 'notification_avatar.dart';
import 'notification_router.dart';
import 'notification_tray.dart';

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

  // Which conversation this is about, if it is about one at all. The tag
  // every chat notification carries, and what a thread takes its own back
  // out of the tray by — see [NotificationTray].
  final String? threadKey = NotificationTray.keyFor(data);

  // The sender's picture, when they have set one. Whether it is there decides
  // more than how the notification looks — see the guard below.
  final String senderImage = (data['senderImage'] ?? '').toString().trim();

  // Android hands a message that carries a `notification` block straight to
  // the tray itself while the app is away — and the plugin wakes this isolate
  // for it all the same, because its receiver sits on the raw FCM broadcast
  // rather than on the messaging service the SDK skips. Raising one here too
  // is how a single message ends up in the shade twice. The foreground is the
  // other way round: nothing is shown for us there, so that path carries on
  // below and is the one that does the showing.
  //
  // One exception, and it is the whole point of the avatar work: a chat
  // message from somebody with a profile picture. FCM's own entry can only
  // ever be the app icon — the v1 payload has no field for a sender's face —
  // so that case deliberately carries on and posts again under the same tag
  // and the same id, which Android takes as an update to the entry already
  // there rather than a second one. What the reader is left with is the
  // notification Messenger gives them: the sender's face, and their message
  // next to it.
  //
  // A chat message from somebody with no picture still returns: there would
  // be nothing to replace FCM's entry with but the same icon it already has.
  //
  // The two data-only notices — the reminder settings above and a new build
  // below — carry no `notification` block and so still run here, which is the
  // whole point of sending them that way.
  final bool replacingTrayEntry =
      fromBackgroundIsolate && message.notification != null;
  if (replacingTrayEntry && (threadKey == null || senderImage.isEmpty)) return;

  // That thread is open in front of the reader, so the message was read as
  // it landed: nothing new belongs in the tray, and whatever was left there
  // before they opened it goes now. Meaningful on the main isolate only — a
  // background message runs where [NotificationTray.openThreadKey] is always
  // null, which is right, because nothing is in front of anybody.
  if (!fromBackgroundIsolate &&
      threadKey != null &&
      threadKey == NotificationTray.openThreadKey) {
    await NotificationTray.clearThread(threadKey);
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
    // Do not show notification to the user who sent the message. On the group
    // topic that now takes an extra step: the sender is subscribed to it like
    // everybody else, so FCM has already put their own message into their own
    // shade before this isolate ran, and the only way it leaves again is if
    // this takes it out.
    if (replacingTrayEntry) {
      await _initialiseForBackground(FlutterLocalNotificationsPlugin());
      await NotificationTray.clearThread(threadKey);
    }
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

  // Whether the lines above found something worth saying that the message
  // itself does not say — a mention, a reply. A chat notification drawn in
  // the messaging style has no title of its own to put it in, so this is what
  // decides whether the conversation gets titled with it instead of with its
  // own name.
  final bool titleIsSpecial = displayTitle != title;

  final FlutterLocalNotificationsPlugin localNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  if (fromBackgroundIsolate) {
    await _initialiseForBackground(localNotificationsPlugin);
  }

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'high_importance_channel',
    'High Importance Notifications',
    description: 'This channel is used for important notifications.',
    importance: Importance.high,
  );

  // The pictures, fetched before anything is posted: a notification carries
  // bitmaps, not links, so whatever is going to be on it has to be in hand
  // first. Only a chat message has a face to fetch, and only a message that
  // came with a face is worth fetching a photo for — without one the
  // notification is the plain one it has always been.
  final Uint8List? avatar =
      threadKey == null ? null : await NotificationAvatar.bytesFor(senderImage);
  final String photoUrl = (data['imageUrl'] ?? '').toString().trim();
  final Uint8List? photo = avatar == null || photoUrl.isEmpty
      ? null
      : await NotificationAvatar.bytesFor(photoUrl, large: true);

  // FCM's own entry has to be in the tray before this one can replace it —
  // see [NotificationTray.awaitEntry].
  if (replacingTrayEntry) await NotificationTray.awaitEntry(threadKey!);

  await localNotificationsPlugin.show(
    // A tagged entry keeps the id every tagged entry has, so the one posted
    // here and the one FCM posts while the app is away are one entry rather
    // than two — see [NotificationTray.taggedId].
    threadKey == null ? message.hashCode : NotificationTray.taggedId,
    displayTitle,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        channel.id,
        channel.name,
        channelDescription: channel.description,
        icon: '@drawable/ic_notification',
        color: const Color(AppConstant.notificationAccent),
        importance: Importance.high,
        priority: Priority.high,
        tag: threadKey,
        // Replacing FCM's entry is an update to a notification the reader has
        // already been buzzed for. Alerting again for the same message would
        // be a second buzz for one arrival.
        onlyAlertOnce: replacingTrayEntry,
        styleInformation: _chatStyle(
          avatar: avatar,
          photo: photo,
          body: body,
          senderName: senderName,
          senderPhone: senderPhone?.toString(),
          currentUserName: currentUserName,
          currentUserPhone: currentUserPhone,
          isGroup: data['type'] == 'chat_message',
          groupName: (data['groupName'] ?? '').toString().trim(),
          specialTitle: titleIsSpecial ? displayTitle : null,
        ),
      ),
    ),
    payload: jsonEncode(message.data),
  );
}

/// Sets the local notifications plugin up on an isolate that has never seen
/// it — every background message runs on one.
///
/// Deliberately without a tap callback: this is the same plugin singleton the
/// main isolate's [PushNotificationService.init] configures, and handing
/// `initialize` no callback there would leave every tap going nowhere. In a
/// background isolate there is nothing to navigate anyway — a tap on what is
/// posted here reaches the app through
/// `getNotificationAppLaunchDetails` at the next launch.
Future<void> _initialiseForBackground(
    FlutterLocalNotificationsPlugin plugin) async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@drawable/ic_notification');
  const DarwinInitializationSettings iosSettings =
      DarwinInitializationSettings();
  const InitializationSettings initSettings =
      InitializationSettings(android: androidSettings, iOS: iosSettings);

  await plugin.initialize(initSettings);
}

/// How a chat notification is drawn once the sender's face is in hand.
///
/// Null for everything else — an expense, an announcement, a new build, or a
/// sender who has never set a picture — and those keep the plain notification
/// they have always had.
///
/// Two shapes, and the difference is what arrived:
///
///   • A photo becomes the big picture, with the face as the large icon. The
///     messaging style has no room for a sent picture, and losing the preview
///     to gain a smaller avatar would be a poor trade.
///
///   • Anything else becomes the messaging style, which is the one Android
///     draws the way a chat app is expected to look: the sender's face in a
///     circle, their name, and their words beside it. It ignores the
///     notification's own title, so what the title had to say — a mention, a
///     reply — is carried by [specialTitle] into the conversation title
///     instead, and the group falls back to its own name.
StyleInformation? _chatStyle({
  required Uint8List? avatar,
  required Uint8List? photo,
  required String body,
  required String senderName,
  required String? senderPhone,
  required String currentUserName,
  required String currentUserPhone,
  required bool isGroup,
  required String groupName,
  required String? specialTitle,
}) {
  if (avatar == null) return null;

  if (photo != null) {
    return BigPictureStyleInformation(
      ByteArrayAndroidBitmap(photo),
      largeIcon: ByteArrayAndroidBitmap(avatar),
      contentTitle: specialTitle ?? senderName,
      summaryText: body,
    );
  }

  final Person sender = Person(
    key: senderPhone,
    name: senderName,
    icon: ByteArrayAndroidIcon(avatar),
    important: true,
  );

  return MessagingStyleInformation(
    // The reader themselves. Nothing of theirs is shown on a notification
    // about somebody else's message, but the style is built around knowing
    // which side of the conversation it is on.
    Person(
      key: currentUserPhone,
      name: currentUserName.isEmpty ? 'You' : currentUserName,
    ),
    conversationTitle:
        specialTitle ?? (isGroup ? (groupName.isEmpty ? null : groupName) : null),
    groupConversation: isGroup,
    messages: <Message>[Message(body, DateTime.now(), sender)],
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

    // The web build only *sends* notifications — the send path is plain HTTP
    // and needs none of this setup. Receiving would take a service worker, a
    // VAPID key, and above all a server to do the topic subscriptions:
    // delivery here rides on FCM topics, and the web SDK cannot join one.
    if (kIsWeb) {
      _isInitialized = true;
      return;
    }

    print('FCM: Starting PushNotificationService initialization...');

    // 1. Initialize local notifications FIRST
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@drawable/ic_notification');
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
    syncBroadcastSubscription();

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
    if (kIsWeb) return;
    try {
      await _fcm.subscribeToTopic('group_chat');
      print('FCM: Successfully subscribed to group_chat topic');
    } catch (e) {
      print('FCM: Error subscribing to group_chat topic: $e');
    }
  }

  /// Joins or leaves the broadcast topic to match the account's type.
  ///
  /// Everything sent to the whole house — group messages, announcements,
  /// meals, expenses — goes out on this one topic, so leaving it is what
  /// keeps a general user's phone quiet about a house life they are not part
  /// of. Their personal topic stays: direct messages and role changes are
  /// still theirs. Called at app start, after sign-in, and by the splash once
  /// it has re-read the account, so an admin's change lands with the role.
  Future<void> syncBroadcastSubscription() async {
    if (kIsWeb) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool general = prefs.getString(AppConstant.keyUserType) ==
          AppConstant.userTypeGeneral;

      if (general) {
        await _fcm.unsubscribeFromTopic('group_chat');
        print('FCM: General user — left the group_chat topic');
      } else {
        await _fcm.subscribeToTopic('group_chat');
        print('FCM: Successfully subscribed to group_chat topic');
      }
    } catch (e) {
      print('FCM: Error syncing group_chat topic: $e');
    }
  }

  Future<void> subscribeToUserTopic(String phone) async {
    if (kIsWeb || phone.isEmpty) return;
    try {
      String safePhone = phone.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '');
      await _fcm.subscribeToTopic('user_$safePhone');
      print('FCM: Successfully subscribed to personal topic: user_$safePhone');
    } catch (e) {
      print('FCM: Error subscribing to personal topic: $e');
    }
  }

  /// ------------------------------------------------ master notification gate

  /// The last answer the master switch gave, and when — see
  /// [_notificationsAllowed]. Statics rather than fields: the service is
  /// constructed freshly in several places, and every copy must share one
  /// answer.
  static bool? _gateOpen;
  static DateTime? _gateReadAt;

  /// How long one answer stands before the document is asked again. Long
  /// enough that a burst of chat messages costs one read, short enough that
  /// an admin flipping the switch reaches every other device's sends within
  /// about a minute.
  static const Duration _gateTtl = Duration(seconds: 45);

  /// Applies a just-saved answer at once, so the admin who flipped the switch
  /// is not sending against their own stale cache for another TTL.
  static void primeGate(bool allowed) {
    _gateOpen = allowed;
    _gateReadAt = DateTime.now();
  }

  /// Whether the house's master notification switch is on.
  ///
  /// Asked of `config/business_config` itself rather than of a copy pushed
  /// around: a silenced house must stay silent even on a device that missed
  /// every announcement of the fact. Firestore answers from its own offline
  /// cache when the network is down; failing even that, the launch-cached
  /// config stands in; failing everything, the switch reads as on — a lost
  /// notification is a smaller failure than a house that went quiet because
  /// one read timed out.
  static Future<bool> _notificationsAllowed() async {
    final DateTime now = DateTime.now();
    if (_gateOpen != null &&
        _gateReadAt != null &&
        now.difference(_gateReadAt!) < _gateTtl) {
      return _gateOpen!;
    }

    bool allowed = true;
    try {
      final DocumentSnapshot<Map<String, dynamic>> doc =
          await FirebaseFirestore.instance
              .collection(AppConstant.collectionConfig)
              .doc(AppConstant.docBusinessConfig)
              .get()
              .timeout(const Duration(seconds: 6));
      allowed = doc.data()?[AppConstant.fieldNotificationsEnabled] != false;
    } catch (e) {
      print('FCM: master switch read failed ($e) — using cached config');
      try {
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final String? raw = prefs.getString(AppConstant.keyCachedAppConfig);
        if (raw != null && raw.isNotEmpty) {
          final dynamic cached = jsonDecode(raw);
          if (cached is Map) {
            allowed = cached[AppConstant.fieldNotificationsEnabled] != false;
          }
        }
      } catch (_) {
        // Both reads failed; the default above keeps notifications flowing.
      }
    }

    _gateOpen = allowed;
    _gateReadAt = now;
    return allowed;
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

    /// Filled, when a list is handed in, with the phones whose topic did not
    /// take the message. A caller that retries needs this: without it, one
    /// topic failing out of six puts all six back in the queue and the five
    /// people who already had the notification get it a second time.
    List<String>? unreached,
  }) async {
    try {
      // The house's master switch, checked at the one door every push in the
      // app leaves through. Silenced means *pretend delivered*: returning
      // false here would put the message into the outbox's retry loop and
      // jam everything queued behind it, when the whole point is that it
      // must not go out. The reminder_config payload is exempt — it shows
      // nobody anything, it only carries the admin's reminder settings to
      // the other devices, and blocking it would quietly desynchronise them.
      if (data?['type'] != 'reminder_config' &&
          !await _notificationsAllowed()) {
        print('FCM: master notification switch is off — dropped "$title"');
        return true;
      }

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

      // The tag a chat notification is filed under, so the thread it belongs
      // to can take it back out of the tray once it has been read — see
      // [NotificationTray]. It also keeps a burst of messages in one
      // conversation to one line: Android replaces an entry that shares a
      // tag and an id with the one already there.
      final String? threadTag = NotificationTray.keyFor(data ?? const {});

      // The topic, and the phone it stands for — a caller that retries needs
      // to know which people were not reached, not which topics.
      final List<(String topic, String? phone)> targets = [];
      if (targetPhones != null && targetPhones.isNotEmpty) {
        for (final phone in targetPhones) {
          String safePhone = phone.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '');
          final String topic = 'user_$safePhone';
          // One send per topic, however many times a phone was handed in.
          // The same topic twice is the same notification twice, and the
          // callers upstream have more than one way of naming somebody.
          if (targets.any((t) => t.$1 == topic)) continue;
          targets.add((topic, phone));
        }
      } else {
        targets.add(('group_chat', null));
      }

      print("topics : ----> ${targets.map((t) => t.$1).toList()}");

      bool allSent = true;
      for (final (String topic, String? phone) in targets) {
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
                  // Named without the @drawable/ prefix here: FCM resolves the
                  // small icon against the app's drawable resources.
                  'icon': 'ic_notification',
                  'color': '#5B4BF0',
                  if (threadTag != null) 'tag': threadTag,
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

        // Caught per topic rather than around the loop: one topic that
        // times out must not take the people after it in the list with it,
        // and [unreached] has to name every one that did not arrive.
        try {
          // Bounded: a link that is up but not answering must not hold a
          // save.
          final response = await http
              .post(url, headers: headers, body: jsonEncode(payload))
              .timeout(const Duration(seconds: 20));
          if (response.statusCode != 200) {
            print('FCM Send Error [Topic: $topic]: ${response.body}');
            allSent = false;
            if (phone != null) unreached?.add(phone);
          } else {
            print('FCM Send Success [Topic: $topic]');
          }
        } catch (e) {
          print('FCM Send Error [Topic: $topic]: $e');
          allSent = false;
          if (phone != null) unreached?.add(phone);
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
