import '../model/app_config_model.dart';

abstract class SettingsRepository {
  /// The single app-wide config document. A successful read is also written
  /// to the device, for [loadCachedAppConfig].
  Future<AppConfigModel> fetchAppConfig();

  /// The last config that [fetchAppConfig] read, or null when there has never
  /// been one — the splash screen's answer to an offline launch.
  Future<AppConfigModel?> loadCachedAppConfig();

  Future<void> saveAppConfig(Map<String, dynamic> data, {String by = ''});
}
