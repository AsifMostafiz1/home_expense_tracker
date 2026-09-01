import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The notification tray, as far as one conversation is concerned.
///
/// Reading a thread is what empties it — the way it works everywhere else
/// messages are read. Two things make that harder than a single `cancel`:
///
///   • **The app does not post every entry it has to remove.** A chat push
///     carries a `notification` block, so while the app is in the background
///     Android hands it straight to the tray and never wakes the isolate that
///     would have posted it. Those entries belong to FCM, and their ids were
///     never ours to keep. `getActiveNotifications` is the way back to them:
///     on Android it reads the status bar itself, so FCM's entries come back
///     with the id and tag the system knows them by, and cancelling one of
///     those works exactly like cancelling our own.
///
///   • **Which entry belongs to which thread has to be written down.** So
///     every chat notification — the one FCM posts and the one the foreground
///     handler posts — is tagged with [keyFor], and the tag is what a thread
///     recognises its own by. Android identifies a notification by tag *and*
///     id together, so one thread's messages replace each other rather than
///     stacking: one line per conversation, which is what a reader wants from
///     a thread they have not opened yet.
class NotificationTray {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// The house group. One thread for everybody, so one constant.
  static const String groupKey = 'thread_group';

  /// A direct thread, by the conversation id both ends work out the same way
  /// — see `ChatThread.conversationIdFor`.
  static String directKey(String conversationId) => 'thread_$conversationId';

  /// The thread the reader is looking at this second, or null.
  ///
  /// Only ever set on the main isolate, which is the point: a background
  /// message runs somewhere this is always null, and a notification that
  /// arrives while the app is away must be raised whatever screen was last
  /// on it.
  static String? openThreadKey;

  /// Which thread [data] is about, or null for a notification that is not a
  /// message at all — an expense, the rules, a new build. Those keep the tray
  /// behaviour they have always had.
  static String? keyFor(Map<String, dynamic> data) {
    switch (data['type']?.toString()) {
      case 'chat_message':
        return groupKey;
      case 'direct_message':
        final String id = (data['conversationId'] ?? '').toString();
        return id.isEmpty ? null : directKey(id);
      default:
        return null;
    }
  }

  /// The notification id that goes with [key]. Stable, so the entry the
  /// foreground handler posts and the entry FCM posts for the same thread are
  /// one entry rather than two.
  static int idFor(String key) => key.hashCode & 0x7fffffff;

  /// Takes every tray entry belonging to [key] down.
  ///
  /// Best effort by design: `getActiveNotifications` needs Android 6, and a
  /// tray that could not be read is not a reason to fail whatever asked.
  static Future<void> clearThread(String? key) async {
    if (kIsWeb || key == null) return;
    try {
      final List<ActiveNotification> active =
          await _plugin.getActiveNotifications();
      for (final ActiveNotification entry in active) {
        if (entry.tag != key && entry.groupKey != key) continue;
        await _plugin.cancel(entry.id ?? idFor(key), tag: entry.tag);
      }
    } catch (e) {
      debugPrint('NotificationTray: could not clear $key — $e');
    }
  }
}
