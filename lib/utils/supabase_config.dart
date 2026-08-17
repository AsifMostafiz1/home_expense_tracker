/// Supabase is used for one thing only: file/image storage.
///
/// Firestore stays the database — nothing here touches app data. Supabase
/// Storage is here because Firebase Storage requires a billing account on the
/// project, and this one has none.
///
/// The publishable key is safe to ship in the client: it identifies the
/// project, not a user, and every bucket operation is still gated by the
/// storage policies set in the Supabase dashboard. Never put the *service
/// role* / secret key here — that one bypasses every policy.
class SupabaseConfig {
  /// Project URL — Supabase dashboard → Project Settings → Data API.
  /// Looks like `https://abcdefghijklm.supabase.co`.
  static const String url = 'https://geeubfgtlcfxswrzflaj.supabase.co';

  /// Publishable key — Project Settings → API Keys. Newer projects show it as
  /// `sb_publishable_…`; older ones label the same slot `anon` `public` and
  /// hand you a JWT. Either value goes here.
  static const String publishableKey =
      'sb_publishable_sDvMp79EbItPrZttf5NlNg_sNcfYogX';

  /// Bucket that holds every upload. Create it under Storage → New bucket and
  /// mark it **Public** so the stored URLs render without a signed request.
  static const String bucket = 'uploads';

  /// Folders inside the bucket, so objects stay grouped by what they belong to.
  static const String folderProfile = 'profile';
  static const String folderChat = 'chat';

  static bool get isConfigured =>
      url != 'YOUR_SUPABASE_PROJECT_URL' &&
      publishableKey != 'YOUR_SUPABASE_PUBLISHABLE_KEY' &&
      url.isNotEmpty &&
      publishableKey.isNotEmpty;
}
