import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../services/background_sync_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../utils/app_constant.dart';
import '../model/debt_entry.dart';
import '../model/ledger_person.dart';
import '../model/personal_transaction.dart';
import 'personal_repository.dart';

/// Firestore-backed and offline-first, the same shape as the meal and expense
/// repositories.
///
/// Both streams read a member's whole ledger rather than one month of it. A
/// personal book runs to hundreds of rows, not millions; holding it in memory
/// makes every month switch, chart and person balance instant, and keeps the
/// queries to a single equality filter — no composite index to deploy, and no
/// second read when the month changes.
class PersonalRepositoryImpl implements PersonalRepository {
  final ConnectivityService? connectivity;

  PersonalRepositoryImpl({this.connectivity});

  static const Duration _ackTimeout = Duration(seconds: 8);

  CollectionReference<Map<String, dynamic>> get _transactions =>
      FirebaseFirestore.instance
          .collection(AppConstant.collectionPersonalTransactions);

  CollectionReference<Map<String, dynamic>> get _debts =>
      FirebaseFirestore.instance.collection(AppConstant.collectionPersonalDebts);

  CollectionReference<Map<String, dynamic>> get _people =>
      FirebaseFirestore.instance
          .collection(AppConstant.collectionPersonalPeople);

  @override
  Stream<List<PersonalTransaction>> watchTransactions(String ownerPhone) {
    if (ownerPhone.isEmpty) {
      return Stream<List<PersonalTransaction>>.value(const []);
    }

    return _transactions
        .where('owner_phone', isEqualTo: ownerPhone)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      if (!snapshot.metadata.isFromCache) connectivity?.reportReachable();

      final List<PersonalTransaction> items = snapshot.docs
          .map((doc) => PersonalTransaction.fromMap(
                doc.id,
                doc.data(),
                pending: doc.metadata.hasPendingWrites,
              ))
          .toList();

      // Newest first, and sorted here rather than by the query: an `orderBy`
      // alongside the filter would want a composite index for a list this
      // side can sort in microseconds. Two entries on the same day fall back
      // to the clock, so the order matches the order they happened in.
      items.sort((a, b) {
        final int byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.minuteOfDay.compareTo(a.minuteOfDay);
      });
      return items;
    });
  }

  @override
  Future<void> saveTransaction(PersonalTransaction transaction) {
    final Map<String, dynamic> data = {
      ...transaction.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (transaction.id.isEmpty) {
      return _commit(_transactions.doc().set({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      }));
    }

    return _commit(
        _transactions.doc(transaction.id).set(data, SetOptions(merge: true)));
  }

  @override
  Future<void> deleteTransaction(String id) =>
      _commit(_transactions.doc(id).delete());

  @override
  Stream<List<DebtEntry>> watchDebts(String ownerPhone) {
    if (ownerPhone.isEmpty) return Stream<List<DebtEntry>>.value(const []);

    return _debts
        .where('owner_phone', isEqualTo: ownerPhone)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      if (!snapshot.metadata.isFromCache) connectivity?.reportReachable();

      final List<DebtEntry> items = snapshot.docs
          .map((doc) => DebtEntry.fromMap(
                doc.id,
                doc.data(),
                pending: doc.metadata.hasPendingWrites,
              ))
          .toList();

      items.sort((a, b) {
        final int byDate = b.date.compareTo(a.date);
        return byDate != 0 ? byDate : b.minuteOfDay.compareTo(a.minuteOfDay);
      });
      return items;
    });
  }

  @override
  Future<void> saveDebtEntry(DebtEntry entry) {
    final Map<String, dynamic> data = {
      ...entry.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (entry.id.isEmpty) {
      return _commit(_debts.doc().set({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      }));
    }

    return _commit(_debts.doc(entry.id).set(data, SetOptions(merge: true)));
  }

  @override
  Future<void> deleteDebtEntry(String id) => _commit(_debts.doc(id).delete());

  @override
  Stream<List<LedgerPerson>> watchPeople(String ownerPhone) {
    if (ownerPhone.isEmpty) return Stream<List<LedgerPerson>>.value(const []);

    return _people
        .where('owner_phone', isEqualTo: ownerPhone)
        .snapshots(includeMetadataChanges: true)
        .map((snapshot) {
      if (!snapshot.metadata.isFromCache) connectivity?.reportReachable();

      final List<LedgerPerson> items = snapshot.docs
          .map((doc) => LedgerPerson.fromMap(
                doc.id,
                doc.data(),
                pending: doc.metadata.hasPendingWrites,
              ))
          .toList();

      // Newest first, so a person added a moment ago is at the top of the
      // list they were added from. A record with no timestamp yet is one this
      // device has just written and Firestore has not stamped — that is the
      // newest of all.
      items.sort((a, b) {
        final DateTime? aAt = a.createdAt;
        final DateTime? bAt = b.createdAt;
        if (aAt == null || bAt == null) {
          if (aAt == bAt) return 0;
          return aAt == null ? -1 : 1;
        }
        return bAt.compareTo(aAt);
      });
      return items;
    });
  }

  @override
  Future<void> savePerson(LedgerPerson person) {
    final Map<String, dynamic> data = {
      ...person.toMap(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (person.id.isEmpty) {
      return _commit(_people.doc().set({
        ...data,
        'createdAt': FieldValue.serverTimestamp(),
      }));
    }

    return _commit(_people.doc(person.id).set(data, SetOptions(merge: true)));
  }

  @override
  Future<void> renamePerson({
    required List<DebtEntry> entries,
    List<String> personIds = const [],
    required String name,
  }) {
    if (entries.isEmpty && personIds.isEmpty) return Future<void>.value();

    // One batch, so the account is never half renamed — a run of separate
    // writes interrupted midway would leave the rows split across two keys
    // and show the person twice on the dues list.
    final WriteBatch batch = FirebaseFirestore.instance.batch();
    final Map<String, dynamic> data = {
      'person_name': name,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // `update` rather than `set`: every one of these came out of a live
    // snapshot, so a document that is not there is a bug worth hearing about
    // rather than something to quietly create half of.
    for (final DebtEntry entry in entries) {
      if (entry.id.isNotEmpty) batch.update(_debts.doc(entry.id), data);
    }
    for (final String id in personIds) {
      if (id.isNotEmpty) batch.update(_people.doc(id), data);
    }
    return _commit(batch.commit());
  }

  @override
  Future<void> deletePerson(
    List<DebtEntry> entries, {
    List<String> personIds = const [],
  }) {
    if (entries.isEmpty && personIds.isEmpty) return Future<void>.value();

    final WriteBatch batch = FirebaseFirestore.instance.batch();
    for (final DebtEntry entry in entries) {
      batch.delete(_debts.doc(entry.id));
    }
    for (final String id in personIds) {
      if (id.isNotEmpty) batch.delete(_people.doc(id));
    }
    return _commit(batch.commit());
  }

  /// Waits for the server's acknowledgement while online — a rejected write
  /// still surfaces as an error — and returns at once when offline, leaving
  /// the write in Firestore's queue for the next connection.
  Future<void> _commit(Future<void> write) async {
    if (connectivity?.isOffline ?? false) {
      unawaited(write.catchError(
        (Object e) => debugPrint('Personal: queued write failed — $e'),
      ));
      BackgroundSyncService.schedule();
      return;
    }

    try {
      await write.timeout(_ackTimeout);
    } on TimeoutException {
      debugPrint('Personal: write not acknowledged in time — queued');
      BackgroundSyncService.schedule();
    }
  }
}
