class AppConstant {
  static const String appName = 'Meal Tracker';
  
  // Shared Preferences Keys
  static const String keyIsLoggedIn = 'isLoggedIn';
  static const String keyUserPhone = 'userPhone';
  static const String keyUserName = 'userName';
  static const String keyUserProfileImage = 'userProfileImage';
  static const String keyThemeMode = 'themeMode';
  static const String keyLanguage = 'language';
  static const String keyRememberMe = 'rememberMe';
  static const String keySavedPhone = 'savedPhone';
  static const String keySavedPassword = 'savedPassword';
  static const String keyIsAdmin = 'isAdmin';
  static const String keyDismissedAnnouncementId = 'dismissedAnnouncementId';

  /// Set once the OS notification prompt has been shown at least once, so a
  /// later refusal can be told apart from a first launch.
  static const String keyNotificationPermissionAsked =
      'notificationPermissionAsked';

  /// Set once the member has closed the "add a profile photo" sheet the home
  /// screen raises. Keyed by phone number rather than kept global: a shared
  /// device can hold more than one account, and each of them is asked once.
  /// Deliberately left behind by sign-out — the answer belongs to the account,
  /// not to the session.
  static String keyProfilePhotoPromptDismissed(String phone) => 'profilePhotoPromptDismissed_$phone';

  /// The last `config/business_config` document that was read, as JSON. The
  /// splash screen falls back to it when the read fails, so an offline launch
  /// still gets through the version gate instead of stalling on it.
  static const String keyCachedAppConfig = 'cachedAppConfig';

  /// Receipts picked while offline, keyed by expense id, waiting to be
  /// uploaded — see `ReceiptOutboxService`.
  static const String keyPendingReceipts = 'pendingReceipts';

  /// Chat messages sent but not yet delivered — see `ChatOutboxService`.
  static const String keyChatOutbox = 'chatOutbox';


  // Firestore Collection Names
  static const String collectionUsers = 'users';
  static const String collectionMeals = 'meals';
  static const String collectionExpenses = 'expenses';
  static const String collectionConfig = 'config';
  static const String collectionAnnouncements = 'announcements';
  static const String collectionChats = 'chats';
  static const String collectionSeenStatus = 'seen_status';
  static const String collectionEditLogs = 'edit_logs';

  /// One document per month, keyed `YYYY-MM` — the house bills an admin sets
  /// up from the monthly statistics screen.
  static const String collectionMonthlyBills = 'monthly_bills';
  
  static const double appVersion = 1.0;
  static const String docBusinessConfig = 'business_config';
}
