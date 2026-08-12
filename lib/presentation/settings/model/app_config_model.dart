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

  double get versionValue => double.tryParse(appVersion.trim()) ?? 0;

  bool get isEmpty => appVersion.isEmpty && downloadLink.isEmpty;

  factory AppConfigModel.fromMap(Map<String, dynamic> map) {
    return AppConfigModel(
      appVersion: (map['app_version'] ?? '').toString(),
      downloadLink: (map['app_download_link'] ?? '').toString(),
      updatedBy: map['updated_by'] ?? '',
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() => {
        'app_version': appVersion,
        'app_download_link': downloadLink,
      };
}
