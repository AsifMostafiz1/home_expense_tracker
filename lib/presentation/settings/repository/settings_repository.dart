import '../model/app_config_model.dart';

abstract class SettingsRepository {
  /// The single app-wide config document. A successful read is also written
  /// to the device, for [loadCachedAppConfig].
  Future<AppConfigModel> fetchAppConfig();

  /// The last config that [fetchAppConfig] read, or null when there has never
  /// been one — the splash screen's answer to an offline launch.
  Future<AppConfigModel?> loadCachedAppConfig();

  Future<void> saveAppConfig(Map<String, dynamic> data, {String by = ''});

  /// The phone numbers of everyone whose last-seen build is behind
  /// [version] — who a "new version" notice is for, and nobody else.
  ///
  /// Read from what each device stamps on its own record at launch. A member
  /// who has never stamped one counts as behind: the field only appears once
  /// they have opened a build that writes it.
  Future<List<String>> fetchPhonesBehind(double version);
}
