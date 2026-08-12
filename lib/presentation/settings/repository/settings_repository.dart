import '../model/app_config_model.dart';

abstract class SettingsRepository {
  /// The single app-wide config document.
  Future<AppConfigModel> fetchAppConfig();

  Future<void> saveAppConfig(Map<String, dynamic> data, {String by = ''});
}
