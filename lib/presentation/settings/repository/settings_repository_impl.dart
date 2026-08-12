import 'package:cloud_firestore/cloud_firestore.dart';

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

    return AppConfigModel.fromMap(snapshot.data() ?? {});
  }

  @override
  Future<void> saveAppConfig(Map<String, dynamic> data, {String by = ''}) async {
    // Merged: the document is shared with anything else the app may keep in
    // its business config, and this screen only owns two of its fields.
    await _doc.set({
      ...data,
      'updated_by': by,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
