import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../services/background_sync_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../utils/app_constant.dart';
import '../model/expense_model.dart';
import 'expense_repository.dart';

/// Firestore-backed, and offline-first.
///
/// Firestore keeps a local copy of everything it has read and a queue of every
/// write it has not yet delivered — the persistence switched on in `main`. A
/// write lands in that store immediately; the future Firestore hands back only
/// completes once the *server* has acknowledged it, which offline is never.
/// So the writes here wait for that acknowledgement only while there is a
/// connection to wait on, and even then not for long — a timeout is not a
/// failure, the write is still queued and goes out with the next connection.
class ExpenseRepositoryImpl implements ExpenseRepository {
  /// Optional: the background sync builds one of these with no service at
  /// all — it only ever runs with a network, so every write there just waits
  /// for its acknowledgement.
  final ConnectivityService? connectivity;

  ExpenseRepositoryImpl({this.connectivity});

  /// How long a save waits for the server while online. Long enough for a
  /// slow mobile link to answer, short enough that a link the OS believes is
  /// up but that goes nowhere does not hold the sheet hostage.
  static const Duration _ackTimeout = Duration(seconds: 8);

  /// A server read that has not answered by then is treated as offline.
  static const Duration _readTimeout = Duration(seconds: 15);

  CollectionReference<Map<String, dynamic>> get _collection =>
      FirebaseFirestore.instance.collection(AppConstant.collectionExpenses);

  @override
  Future<List<ExpenseModel>> fetchExpenses(
    String userPhone, {
    bool fromCache = false,
  }) async {
    final Query<Map<String, dynamic>> query =
        _collection.where('user_phone', isEqualTo: userPhone);

    final QuerySnapshot<Map<String, dynamic>> snapshot = fromCache
        ? await query.get(const GetOptions(source: Source.cache))
        : await query
            .get(const GetOptions(source: Source.server))
            .timeout(_readTimeout);

    return snapshot.docs.map((doc) {
      return ExpenseModel.fromMap(
        doc.id,
        doc.data(),
        isPending: doc.metadata.hasPendingWrites,
      );
    }).toList();
  }

  @override
  Future<String> addExpense(Map<String, dynamic> data) async {
    // The id is minted on the device, so the caller has it straight away —
    // a receipt queued for later upload needs something to be filed under.
    final DocumentReference<Map<String, dynamic>> ref = _collection.doc();
    await _commit(ref.set(data));
    return ref.id;
  }

  @override
  Future<void> updateExpense(String expenseId, Map<String, dynamic> data) =>
      _commit(_collection.doc(expenseId).update(data));

  @override
  Future<void> deleteExpense(String expenseId) =>
      _commit(_collection.doc(expenseId).delete());

  /// Waits for the server's acknowledgement while online — a rejected write
  /// (rules, a document that no longer exists) still surfaces as an error —
  /// and returns at once when offline, leaving the write in Firestore's queue.
  Future<void> _commit(Future<void> write) async {
    if (connectivity?.isOffline ?? false) {
      // Nobody will collect the eventual result: log it rather than let it
      // surface as an unhandled error much later.
      unawaited(write.catchError(
        (Object e) => debugPrint('Expense: queued write failed — $e'),
      ));
      // Firestore will deliver this itself if the app stays alive; the OS
      // job covers the case where it does not — see BackgroundSyncService.
      BackgroundSyncService.schedule();
      return;
    }

    try {
      await write.timeout(_ackTimeout);
    } on TimeoutException {
      // The link is up but not answering. The write is stored and queued
      // exactly as it would be offline; the list shows it as pending.
      debugPrint('Expense: write not acknowledged in time — queued');
      BackgroundSyncService.schedule();
    }
  }
}
