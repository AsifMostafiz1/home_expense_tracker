import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;
import 'package:workmanager/workmanager.dart';

import '../presentation/chat/repository/chat_repository_impl.dart';
import '../presentation/expense/repository/expense_repository_impl.dart';
import '../utils/supabase_config.dart';
import 'chat_outbox_service.dart';
import 'daily_reminder_service.dart';
import 'push_outbox_service.dart';
import 'receipt_outbox_service.dart';
import 'supabase_storage_service.dart';

/// Sync that survives the app being closed.
///
/// Firestore delivers what was saved offline on its own — but only while the
/// app's process is alive. Swipe the app away before the connection returns
/// and the queue sits on disk until the next launch. This hands that last
/// step to the OS: a job constrained to "has a network" that wakes a headless
/// Dart isolate, drains Firestore's queue and uploads the receipts waiting in
/// the outbox, then goes away.
///
/// Android runs it through WorkManager — reliably, within moments of the
/// network returning, app open or not. iOS has no equivalent: the closest is
/// a `BGProcessingTask`, which iOS runs when *it* decides the moment is right
/// (typically idle and charging), so there it is a "sometime later" rather
/// than a "right away". Either way the app still syncs itself the moment it
/// is opened; this is the path for when it is not.
///
/// Armed by whatever leaves work behind — a write that was not acknowledged,
/// a receipt that could not be uploaded — and disarmed once a read shows
/// nothing pending, so a healthy online session never registers anything.
class BackgroundSyncService {
  BackgroundSyncService._();

  /// One job at a time, under one name. On iOS this is also the
  /// `BGTaskSchedulerPermittedIdentifiers` entry in Info.plist.
  static const String uniqueName = 'com.mostafizur.expense.tracker.sync';
  static const String taskName = 'syncPendingWrites';

  static bool _armed = false;

  /// Registers the callback the OS will run. Once, from `main`.
  static Future<void> init() async {
    // No OS to hand the job to on web — a closed tab is simply gone. The
    // in-app flushes still run; only the "app never reopened" path is lost.
    if (kIsWeb) return;
    try {
      await Workmanager().initialize(callbackDispatcher);
    } catch (e) {
      debugPrint('BackgroundSync: initialize failed — $e');
    }
  }

  /// Asks the OS to run [runSync] once there is a network. Cheap to call as
  /// often as needed: nothing is registered while an armed job is pending.
  static Future<void> schedule() async {
    if (kIsWeb || _armed) return;
    _armed = true;

    try {
      if (Platform.isIOS) {
        await Workmanager().registerProcessingTask(
          uniqueName,
          taskName,
          constraints: Constraints(networkType: NetworkType.connected),
        );
      } else {
        await Workmanager().registerOneOffTask(
          uniqueName,
          taskName,
          constraints: Constraints(networkType: NetworkType.connected),
          // A job already waiting is the same job; do not reset it.
          existingWorkPolicy: ExistingWorkPolicy.keep,
          backoffPolicy: BackoffPolicy.exponential,
          backoffPolicyDelay: const Duration(seconds: 30),
        );
      }
      debugPrint('BackgroundSync: job armed');
    } catch (e) {
      _armed = false;
      debugPrint('BackgroundSync: schedule failed — $e');
    }
  }

  /// Nothing left to deliver. The next offline save arms the job again.
  static void disarm() => _armed = false;

  /// The work itself. Runs in the headless isolate the OS wakes — no GetX,
  /// no bindings, no widgets — so everything it needs is built right here.
  /// Returns true when nothing is left waiting; false asks the OS to retry
  /// with backoff.
  static Future<bool> runSync() async {
    try {
      await Firebase.initializeApp();
    } catch (e) {
      debugPrint('BackgroundSync: Firebase init failed — $e');
      return false;
    }

    // Same setting the app uses. Firestore is one native instance per
    // process; if the app is alive alongside, this is a no-op.
    try {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
      );
    } catch (_) {}

    bool done = true;

    // Touching Firestore starts its client, which reconnects and sends the
    // queue on its own; this only waits for the acknowledgements. Bounded —
    // WorkManager allows ten minutes, and a network that answers this slowly
    // is better tried again later.
    try {
      await FirebaseFirestore.instance
          .waitForPendingWrites()
          .timeout(const Duration(minutes: 2));
      debugPrint('BackgroundSync: Firestore queue delivered');
    } catch (e) {
      debugPrint('BackgroundSync: Firestore queue not drained — $e');
      done = false;
    }

    // A bare Supabase client rather than Supabase.initialize(): the storage
    // uploads need nothing the full Flutter integration (deep links, auth
    // persistence) sets up, and none of that belongs in a headless run.
    final SupabaseClient? client = SupabaseConfig.isConfigured
        ? SupabaseClient(SupabaseConfig.url, SupabaseConfig.publishableKey)
        : null;
    final SupabaseStorageService storage =
        SupabaseStorageService(client: client);

    // Receipts.
    try {
      final ReceiptOutboxService outbox = ReceiptOutboxService(
        storage: storage,
        // No connectivity service here: the job only runs with a network, so
        // every write simply waits for its acknowledgement.
        repository: ExpenseRepositoryImpl(),
      );
      await outbox.load();
      if (outbox.isNotEmpty) {
        final bool flushed = await outbox.flush();
        debugPrint(
            'BackgroundSync: receipts ${flushed ? 'uploaded' : 'left over'}');
        done = flushed && done;
      }
    } catch (e) {
      debugPrint('BackgroundSync: receipt flush failed — $e');
      done = false;
    }

    // Notifications for writes that were saved offline — announcements, an
    // admin's corrections. After the queue above, so the write they announce
    // is on the server before anyone taps them.
    try {
      final PushOutboxService outbox = PushOutboxService();
      await outbox.load();
      if (outbox.isNotEmpty) {
        final bool flushed = await outbox.flush();
        debugPrint(
            'BackgroundSync: notifications ${flushed ? 'sent' : 'left over'}');
        done = flushed && done;
      }
    } catch (e) {
      debugPrint('BackgroundSync: notification flush failed — $e');
      done = false;
    }

    // Chat messages — write, picture and notification, the same way the app
    // itself would have sent them.
    try {
      final ChatOutboxService outbox = ChatOutboxService(
        storage: storage,
        repository: ChatRepositoryImpl(),
      );
      await outbox.load();
      if (outbox.isNotEmpty) {
        final bool flushed = await outbox.flush();
        debugPrint(
            'BackgroundSync: chat messages ${flushed ? 'sent' : 'left over'}');
        done = flushed && done;
      }
    } catch (e) {
      debugPrint('BackgroundSync: chat flush failed — $e');
      done = false;
    }

    return done;
  }
}

/// Entry point the OS calls in its own isolate. Must be a top-level function
/// and must survive tree shaking, hence the pragma.
///
/// Shared by every background job the app registers — WorkManager allows one
/// callback per app, so the task name is what says which of them was woken.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager()
      .executeTask((String task, Map<String, dynamic>? inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      switch (task) {
        case DailyReminderService.taskName:
          return await DailyReminderService.run();
        default:
          return await BackgroundSyncService.runSync();
      }
    } catch (e) {
      debugPrint('BackgroundSync: task \$task failed — \$e');
      return false;
    }
  });
}
