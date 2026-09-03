import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/supabase_config.dart';

/// Thin wrapper over Supabase Storage — the only upload path in the app.
///
/// Callers get back a plain public URL string, which is what the rest of the
/// app already expects: `users/{phone}.profileImage`, `chats.sender_image`, and
/// every `NetworkImage` reading them stay unchanged.
class SupabaseStorageService {
  /// A client of the caller's own, for where `Supabase.initialize()` has not
  /// run — the headless background sync. Everywhere else the app-wide one.
  final SupabaseClient? _clientOverride;

  SupabaseStorageService({SupabaseClient? client}) : _clientOverride = client;

  SupabaseClient get _client => _clientOverride ?? Supabase.instance.client;

  /// Uploads [file] into [folder] and returns its public URL.
  ///
  /// The object name carries a timestamp rather than a stable id (e.g. the
  /// phone number) on purpose: a public URL that never changes gets held by
  /// the CDN and by Flutter's image cache, so a replaced avatar would keep
  /// showing the old picture until the cache expired.
  Future<String> uploadFile(
    File file, {
    required String folder,
    String? namePrefix,
  }) async {
    final Uint8List bytes = await file.readAsBytes();
    return uploadBytes(
      bytes,
      folder: folder,
      extension: extensionOf(file.path),
      namePrefix: namePrefix,
    );
  }

  /// The picker's own type, which works on every platform: a real file on
  /// mobile, a blob in the browser on web — `readAsBytes` reads both. The
  /// pick-and-upload flows all go through here.
  ///
  /// On web a blob URL carries no extension; [XFile.name] usually still does,
  /// so the extension is read from there.
  Future<String> uploadXFile(
    XFile file, {
    required String folder,
    String? namePrefix,
  }) async {
    final Uint8List bytes = await file.readAsBytes();
    return uploadBytes(
      bytes,
      folder: folder,
      extension: extensionOf(file.name.isNotEmpty ? file.name : file.path),
      namePrefix: namePrefix,
    );
  }

  /// Byte-based variant — used by [uploadFile], and the one to call on web
  /// where `dart:io` files are unavailable (`XFile.readAsBytes()`).
  Future<String> uploadBytes(
    Uint8List bytes, {
    required String folder,
    String extension = '.jpg',
    String? namePrefix,
  }) async {
    if (!SupabaseConfig.isConfigured) {
      throw StateError(
        'Supabase is not configured — fill in SupabaseConfig.url and '
        'SupabaseConfig.publishableKey.',
      );
    }

    final String stamp = DateTime.now().millisecondsSinceEpoch.toString();
    final String name = namePrefix == null ? stamp : '${namePrefix}_$stamp';
    final String objectPath = '$folder/$name$extension';

    await _client.storage.from(SupabaseConfig.bucket).uploadBinary(
          objectPath,
          bytes,
          fileOptions: FileOptions(
            contentType: _contentTypeOf(extension),
            cacheControl: '3600',
            upsert: false,
          ),
        );

    return _client.storage.from(SupabaseConfig.bucket).getPublicUrl(objectPath);
  }

  /// Deletes the object a previously returned public URL points at.
  ///
  /// Best effort — a failure here is logged, not thrown, since losing a
  /// replaced avatar to an orphaned object should not fail the profile save
  /// that already succeeded.
  Future<void> deleteByPublicUrl(String? publicUrl) async {
    final String? objectPath = objectPathFromPublicUrl(publicUrl);
    if (objectPath == null) return;

    try {
      // Bounded, since a caller is usually holding a sheet open on this: a
      // link that is up but not answering must not turn a save into a stall.
      await _client.storage
          .from(SupabaseConfig.bucket)
          .remove([objectPath]).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('Supabase: failed to delete $objectPath — $e');
    }
  }

  /// Pulls the in-bucket path back out of a public URL, or null when the URL
  /// is empty or points somewhere that is not this bucket (an old Firebase
  /// Storage link, say, which must not be treated as ours to delete).
  String? objectPathFromPublicUrl(String? publicUrl) {
    if (publicUrl == null || publicUrl.isEmpty) return null;

    const String marker = '/storage/v1/object/public/';
    final int markerAt = publicUrl.indexOf(marker);
    if (markerAt == -1) return null;

    final String afterMarker = publicUrl.substring(markerAt + marker.length);
    const String prefix = '${SupabaseConfig.bucket}/';
    if (!afterMarker.startsWith(prefix)) return null;

    // Drop any `?token=`/`?t=` style suffix before returning the path.
    return afterMarker.substring(prefix.length).split('?').first;
  }

  /// `.jpg` for anything it cannot read off [path]. Public because callers
  /// that already hold the bytes — the chat, which needs them to measure the
  /// picture — go through [uploadBytes] and have to name the extension.
  String extensionOf(String path) {
    final int dotAt = path.lastIndexOf('.');
    if (dotAt == -1 || dotAt == path.length - 1) return '.jpg';
    return path.substring(dotAt).toLowerCase();
  }

  String _contentTypeOf(String extension) {
    switch (extension) {
      // Voice messages. Named explicitly because the fallback below is an
      // image type: an audio object served as `image/jpeg` is one a browser —
      // and the player on the other end — refuses to open.
      case '.m4a':
      case '.mp4':
        return 'audio/mp4';
      case '.aac':
        return 'audio/aac';
      case '.webm':
        return 'audio/webm';
      case '.ogg':
      case '.opus':
        return 'audio/ogg';
      case '.wav':
        return 'audio/wav';
      case '.mp3':
        return 'audio/mpeg';
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.gif':
        return 'image/gif';
      case '.heic':
        return 'image/heic';
      case '.pdf':
        return 'application/pdf';
      default:
        return 'image/jpeg';
    }
  }
}
