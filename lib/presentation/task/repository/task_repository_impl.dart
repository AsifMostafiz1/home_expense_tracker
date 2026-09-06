import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../services/background_sync_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../utils/app_constant.dart';
import '../model/task_model.dart';
import 'task_repository.dart';

/// Firestore-backed and offline-first, the same shape as the personal
/// ledger: a write lands in the local store at once and only waits for the
/// server's acknowledgement while there is a connection to wait on.
///
/// One stream reads the member's whole list rather than a window of it. A
/// to-do list runs to dozens of rows, hundreds with a year of finished
/// daily tasks behind it — small enough to hold, and holding it is what makes
/// the today / overdue / upcoming piles a fold in memory with a single
/// equality filter behind them and no composite index to deploy.
class TaskRepositoryImpl implements TaskRepository {
  /// Optional — with none, every write simply waits for its acknowledgement.
  final ConnectivityService? connectivity;

  TaskRepositoryImpl({this.connectivity});

  static const Duration _ackTimeout = Duration(seconds: 8);

  CollectionReference<Map<String, dynamic>> get _tasks =>
      FirebaseFirestore.instance.collection(AppConstant.collectionTasks);

  @override
  Stream<List<TaskModel>> watchTasks(String ownerPhone) {
    if (ownerPhone.isEmpty) return Stream<List<TaskModel>>.value(const []);

    return _tasks
        .where('owner_phone', isEqualTo: ownerPhone)
        // Metadata too, for the reason the ledger includes it: a task going
        // from "on this device" to "on the server" changes nothing in its
        // data, and the "waiting to sync" mark on it has to clear all the
        // same.
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      // A snapshot the server answered is proof the internet is reachable,
      // and one arrives far more often than the connectivity probe asks.
      if (!snapshot.metadata.isFromCache) connectivity?.reportReachable();

      final List<TaskModel> items = snapshot.docs
          .map((doc) => TaskModel.fromMap(
                doc.id,
                doc.data(),
                pending: doc.metadata.hasPendingWrites,
              ))
          .toList();
      items.sort(TaskModel.compare);
      return items;
    });
  }

  @override
  Future<void> saveTask(TaskModel task) {
    final Map<String, dynamic> data = {
      ...task.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (task.id.isEmpty) {
      return _commit(_tasks.doc().set({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      }));
    }

    // Merged: the finished flag and its stamp are not part of an edit, and a
    // rewrite must not reopen a task or lose when it was done.
    data.remove('done');
    return _commit(_tasks.doc(task.id).set(data, SetOptions(merge: true)));
  }

  @override
  Future<void> complete(
    TaskModel task, {
    required String doneDate,
    TaskModel? successor,
  }) {
    final WriteBatch batch = FirebaseFirestore.instance.batch();
    batch.set(
      _tasks.doc(task.id),
      {
        'done': true,
        'done_at': FieldValue.serverTimestamp(),
        'done_date': doneDate,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    if (successor != null) {
      // Named from what it follows and the day it lands on, rather than
      // drawn at random: a second tap on the same ring — the local echo not
      // back yet — then rewrites this very document instead of standing a
      // twin of tomorrow's task beside it.
      batch.set(_tasks.doc(successorIdFor(task, successor)), {
        ...successor.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return _commit(batch.commit());
  }

  /// The id the follow-on copy of [task] is written under.
  static String successorIdFor(TaskModel task, TaskModel successor) =>
      '${task.id}_${successor.date}';

  @override
  Future<void> reopen(TaskModel task, {String? successorId}) {
    final WriteBatch batch = FirebaseFirestore.instance.batch();
    batch.set(
      _tasks.doc(task.id),
      {
        'done': false,
        'done_at': FieldValue.delete(),
        'done_date': '',
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    if (successorId != null && successorId.isNotEmpty) {
      batch.delete(_tasks.doc(successorId));
    }
    return _commit(batch.commit());
  }

  @override
  Future<void> deleteTask(String id) => _commit(_tasks.doc(id).delete());

  @override
  Future<void> deleteAll(List<String> ids) {
    if (ids.isEmpty) return Future<void>.value();
    final WriteBatch batch = FirebaseFirestore.instance.batch();
    for (final String id in ids) {
      batch.delete(_tasks.doc(id));
    }
    return _commit(batch.commit());
  }

  /// Waits for the server's acknowledgement while online — a rejected write
  /// still surfaces as an error — and returns at once when offline, leaving
  /// the write in Firestore's queue for the next connection.
  Future<void> _commit(Future<void> write) async {
    if (connectivity?.isOffline ?? false) {
      unawaited(write.catchError(
        (Object e) => debugPrint('Tasks: queued write failed — $e'),
      ));
      BackgroundSyncService.schedule();
      return;
    }

    try {
      await write.timeout(_ackTimeout);
    } on TimeoutException {
      debugPrint('Tasks: write not acknowledged in time — queued');
      BackgroundSyncService.schedule();
    }
  }
}
