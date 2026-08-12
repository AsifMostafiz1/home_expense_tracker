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
