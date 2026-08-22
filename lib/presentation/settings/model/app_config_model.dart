import 'package:cloud_firestore/cloud_firestore.dart';

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

  const AppConfigModel({
    this.appVersion = '',
    this.downloadLink = '',
    this.updatedBy = '',
    this.updatedAt,
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

  bool get isEmpty => appVersion.isEmpty && downloadLink.isEmpty;

  /// Reads either the Firestore document or the JSON [toCacheJson] wrote —
  /// the only difference is how `updatedAt` is stored.
  factory AppConfigModel.fromMap(Map<String, dynamic> map) {
    return AppConfigModel(
      appVersion: (map['app_version'] ?? '').toString(),
      downloadLink: (map['app_download_link'] ?? '').toString(),
      updatedBy: (map['updated_by'] ?? '').toString(),
      updatedAt: _readDate(map['updatedAt']),
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

  /// The whole document, in a form `jsonEncode` accepts — what the splash
  /// screen falls back to when the read fails.
  Map<String, dynamic> toCacheJson() => {
        ...toMap(),
        'updated_by': updatedBy,
        'updatedAt': updatedAt?.toIso8601String(),
      };
}
