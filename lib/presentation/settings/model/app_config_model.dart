import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../utils/app_constant.dart';

/// The `config/business_config` document the splash screen gates every launch
/// on.
///
/// [appVersion] is kept as the raw string it is stored as: the splash screen
/// reads it into a `String` before parsing, so writing a number here would
/// throw there and silently skip the update check for everyone.
class AppConfigModel {
  final String appVersion;
  final String downloadLink;
  final String updatedBy;
  final DateTime? updatedAt;

  /// Whether the house gets the daily meal reminder at all — see
  /// `DailyReminderService`.
  final bool reminderEnabled;

  /// When it goes out, `HH:mm` on a 24-hour clock. Always a valid time:
  /// anything unreadable in the document falls back to [defaultReminderTime],
  /// because the job that reads this runs with no one around to correct it.
  final String reminderTime;

  /// The master switch over every notification the app sends. True unless an
  /// admin has switched the whole system off — and true for a document that
  /// has never held the field, so an existing house keeps its notifications.
  final bool notificationsEnabled;

  /// Six in the evening — after the day's meals are known and before anyone
  /// has gone to bed.
  static const String defaultReminderTime = '18:00';

  const AppConfigModel({
    this.appVersion = '',
    this.downloadLink = '',
    this.updatedBy = '',
    this.updatedAt,
    this.reminderEnabled = false,
    this.reminderTime = defaultReminderTime,
    this.notificationsEnabled = true,
  });

  double get versionValue => versionOf(appVersion);

  /// A version number out of whatever it was stored as. The config document
  /// keeps a string, a device stamps a number on its own record, and an
  /// account that has never stamped one has nothing at all — which counts as
  /// behind every published version.
  static double versionOf(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString().trim()) ?? 0;
  }

  /// The hour of [reminderTime], 0–23.
  int get reminderHour => hourOf(reminderTime);

  /// The minute of [reminderTime], 0–59.
  int get reminderMinute => minuteOf(reminderTime);

  static int hourOf(String time) => _partsOf(time).$1;

  static int minuteOf(String time) => _partsOf(time).$2;

  /// `HH:mm` out of whatever was stored, falling back to
  /// [defaultReminderTime] rather than throwing — a malformed value must not
  /// take the reminder down for the whole house.
  static String normalizeTime(dynamic value) {
    final (int hour, int minute) = _partsOf(value);
    return '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
  }

  static (int, int) _partsOf(dynamic value) {
    final List<String> parts = (value ?? '').toString().trim().split(':');
    if (parts.length != 2) return _defaultParts;

    final int? hour = int.tryParse(parts[0]);
    final int? minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return _defaultParts;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      return _defaultParts;
    }
    return (hour, minute);
  }

  static final (int, int) _defaultParts = (
    int.parse(defaultReminderTime.split(':')[0]),
    int.parse(defaultReminderTime.split(':')[1]),
  );

  bool get isEmpty => appVersion.isEmpty && downloadLink.isEmpty;

  /// Reads either the Firestore document or the JSON [toCacheJson] wrote —
  /// the only difference is how `updatedAt` is stored.
  factory AppConfigModel.fromMap(Map<String, dynamic> map) {
    return AppConfigModel(
      appVersion: (map['app_version'] ?? '').toString(),
      downloadLink: (map['app_download_link'] ?? '').toString(),
      updatedBy: (map['updated_by'] ?? '').toString(),
      updatedAt: _readDate(map['updatedAt']),
      reminderEnabled: map[AppConstant.fieldReminderEnabled] == true,
      reminderTime: normalizeTime(map[AppConstant.fieldReminderTime]),
      // `!= false` rather than `== true`: a missing field means the switch
      // has never been touched, and notifications stay on.
      notificationsEnabled: map[AppConstant.fieldNotificationsEnabled] != false,
    );
  }

  AppConfigModel copyWith({
    String? appVersion,
    String? downloadLink,
    String? updatedBy,
    bool? reminderEnabled,
    String? reminderTime,
    bool? notificationsEnabled,
  }) {
    return AppConfigModel(
      appVersion: appVersion ?? this.appVersion,
      downloadLink: downloadLink ?? this.downloadLink,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedAt: updatedAt,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
      reminderTime: reminderTime ?? this.reminderTime,
      notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    );
  }

  static DateTime? _readDate(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  Map<String, dynamic> toMap() => {
        'app_version': appVersion,
        'app_download_link': downloadLink,
      };

  /// Only the reminder's own two fields, so saving it cannot disturb the
  /// version gate sharing the document — the two tabs of the settings screen
  /// save independently.
  Map<String, dynamic> toReminderMap() => {
        AppConstant.fieldReminderEnabled: reminderEnabled,
        AppConstant.fieldReminderTime: reminderTime,
      };

  /// The master switch alone, for the same reason [toReminderMap] exists:
  /// flipping it must not touch the version gate or the reminder schedule.
  Map<String, dynamic> toGateMap() => {
        AppConstant.fieldNotificationsEnabled: notificationsEnabled,
      };

  /// The whole document, in a form `jsonEncode` accepts — what the splash
  /// screen falls back to when the read fails.
  Map<String, dynamic> toCacheJson() => {
        ...toMap(),
        ...toReminderMap(),
        ...toGateMap(),
        'updated_by': updatedBy,
        'updatedAt': updatedAt?.toIso8601String(),
      };
}
