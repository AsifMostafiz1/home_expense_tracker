import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../services/background_sync_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../utils/app_constant.dart';
import '../model/house_rule_model.dart';
import 'house_rules_repository.dart';

/// Firestore-backed, and offline-first the same way the meal and expense
/// repositories are: a write lands in the local store at once and only waits
/// for the server's acknowledgement while there is a connection to wait on.
class HouseRulesRepositoryImpl implements HouseRulesRepository {
  /// Optional — with none, every write simply waits for its acknowledgement.
  final ConnectivityService? connectivity;

  HouseRulesRepositoryImpl({this.connectivity});

  static const Duration _ackTimeout = Duration(seconds: 8);

  CollectionReference<Map<String, dynamic>> get _rules =>
      FirebaseFirestore.instance.collection(AppConstant.collectionHouseRules);

  @override
  Stream<List<HouseRuleModel>> watchRules() {
    return _rules
        .orderBy('order')
        // Metadata too, for the reason the announcement stream includes it: a
        // rule going from "on this device" to "on the server" changes nothing
        // in its data, and the "waiting to sync" mark on it has to clear all
        // the same.
        .snapshots(includeMetadataChanges: true)
        .map(_rulesOf);
  }

  List<HouseRuleModel> _rulesOf(QuerySnapshot<Map<String, dynamic>> snapshot) {
    // A snapshot the server answered is proof the internet is reachable, and
    // one arrives far more often than the connectivity probe would ask.
    if (!snapshot.metadata.isFromCache) connectivity?.reportReachable();

    final List<HouseRuleModel> rules = snapshot.docs
        .map((doc) => HouseRuleModel.fromMap(
              doc.id,
              doc.data(),
              pending: doc.metadata.hasPendingWrites,
            ))
        .toList();

    // Sorted again here because `orderBy` cannot place two rules that share a
    // position — which is exactly what a reorder made offline looks like
    // until the server settles it. Ties fall back to the id so the list stops
    // shuffling between rebuilds.
    rules.sort((a, b) {
      final int byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
    });
    return rules;
  }

  @override
  Future<void> addRule({
    required String textEn,
    required String textBn,
    required int order,
    required String by,
  }) {
    return _commit(_rules.doc().set({
      'text_en': textEn,
      'text_bn': textBn,
      'order': order,
      'created_by': by,
      'updated_by': by,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }));
  }

  @override
  Future<void> updateRule(
    String id, {
    required String textEn,
    required String textBn,
    required String by,
  }) {
    // Merged: the position is not part of an edit, and a seeded rule keeps
    // whatever it was created with.
    return _commit(_rules.doc(id).set({
      'text_en': textEn,
      'text_bn': textBn,
      'updated_by': by,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)));
  }

  @override
  Future<void> deleteRule(String id) => _commit(_rules.doc(id).delete());

  @override
  Future<void> saveOrder(List<HouseRuleModel> rules, {required String by}) {
    final WriteBatch batch = FirebaseFirestore.instance.batch();
    for (int i = 0; i < rules.length; i++) {
      batch.set(
        _rules.doc(rules[i].id),
        {'order': i, 'updated_by': by, 'updatedAt': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
    }
    return _commit(batch.commit());
  }

  @override
  Future<void> seedRules(List<HouseRuleModel> rules, {required String by}) {
    final WriteBatch batch = FirebaseFirestore.instance.batch();
    for (final HouseRuleModel rule in rules) {
      batch.set(_rules.doc(rule.id), {
        ...rule.toMap(),
        'created_by': by,
        'updated_by': by,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return _commit(batch.commit());
  }

  /// Waits for the server's acknowledgement while online — a rejected write
  /// still surfaces as an error — and returns at once when offline, leaving
  /// the write in Firestore's queue for the next connection.
  Future<void> _commit(Future<void> write) async {
    if (connectivity?.isOffline ?? false) {
      unawaited(write.catchError(
        (Object e) => debugPrint('House rules: queued write failed — $e'),
      ));
      BackgroundSyncService.schedule();
      return;
    }

    try {
      await write.timeout(_ackTimeout);
    } on TimeoutException {
      debugPrint('House rules: write not acknowledged in time — queued');
      BackgroundSyncService.schedule();
    }
  }
}
