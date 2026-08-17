import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/app_constant.dart';
import '../model/app_config_model.dart';
import 'settings_repository.dart';

class SettingsRepositoryImpl implements SettingsRepository {
  DocumentReference<Map<String, dynamic>> get _doc => FirebaseFirestore.instance
      .collection(AppConstant.collectionConfig)
      .doc(AppConstant.docBusinessConfig);

  @override
  Future<AppConfigModel> fetchAppConfig() async {
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await _doc.get();
    if (!snapshot.exists) return const AppConfigModel();

    final AppConfigModel config = AppConfigModel.fromMap(snapshot.data() ?? {});
    await _cache(config);
    return config;
  }

  @override
  Future<AppConfigModel?> loadCachedAppConfig() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(AppConstant.keyCachedAppConfig);
      if (raw == null || raw.isEmpty) return null;

      return AppConfigModel.fromMap(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } catch (e) {
      debugPrint('Config: cached copy unreadable — $e');
      return null;
    }
  }

  /// Best effort: a cache that fails to write costs nothing now, only a
  /// fallback later.
  Future<void> _cache(AppConfigModel config) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        AppConstant.keyCachedAppConfig,
        jsonEncode(config.toCacheJson()),
      );
    } catch (e) {
      debugPrint('Config: could not cache — $e');
    }
  }

  @override
  Future<void> saveAppConfig(Map<String, dynamic> data,
      {String by = ''}) async {
    // Merged: the document is shared with anything else the app may keep in
    // its business config, and this screen only owns two of its fields.
    await _doc.set({
      ...data,
      'updated_by': by,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
