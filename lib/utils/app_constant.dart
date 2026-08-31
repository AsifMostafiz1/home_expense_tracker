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

  /// 'meal' or 'general' — which side of the app this account gets. Mirrored
  /// from the user document by the splash on every launch, the same way the
  /// admin flag is, so an admin's change lands at the member's next launch.
  static const String keyUserType = 'userType';
  static const String keyDismissedAnnouncementId = 'dismissedAnnouncementId';

  /// The values [keyUserType] — and the `userType` field on a user document —
  /// can hold. A document without the field is a meal user, so every account
  /// that existed before the field did keeps the access it always had.
  static const String userTypeMeal = 'meal';
  static const String userTypeGeneral = 'general';

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

  /// This account's house-rule acknowledgements, mirrored from Firestore as
  /// `{ruleId: version}` JSON. The launch gate reads it before the network
  ///
  ///
  /// answers, so an offline start does not ask again for rules already
  /// agreed to.
  static String keyHouseRuleAcks(String phone) => 'houseRuleAcks_$phone';

  /// Push notifications that could not go out yet — see `PushOutboxService`.
  static const String keyPushOutbox = 'pushOutbox';


  // Firestore Collection Names
  static const String collectionUsers = 'users';
  static const String collectionMeals = 'meals';
  static const String collectionExpenses = 'expenses';
  static const String collectionConfig = 'config';
  static const String collectionAnnouncements = 'announcements';
  static const String collectionChats = 'chats';
  static const String collectionSeenStatus = 'seen_status';

  /// One document per pair of members — see `DirectThread`. The id is both
  /// phone numbers, sorted and joined, so either end builds the same one.
  /// Messages live in a `messages` subcollection under it, read receipts in
  /// a `seen` one.
  static const String collectionDirectChats = 'direct_chats';

  /// Messages an occupant has pinned to the top of the group thread. One
  /// document per pinned message, keyed by the message's own id — a message
  /// can only be pinned once, and unpinning is deleting the document.
  static const String collectionPinnedMessages = 'pinned_messages';

  /// Subcollections of a direct thread.
  static const String subcollectionMessages = 'messages';
  static const String subcollectionSeen = 'seen';
  static const String collectionEditLogs = 'edit_logs';

  /// One document per month, keyed `YYYY-MM` — the house bills an admin sets
  /// up from the monthly statistics screen.
  static const String collectionMonthlyBills = 'monthly_bills';

  /// One document per house rule, each holding both languages — see
  /// `HouseRuleModel`.
  static const String collectionHouseRules = 'house_rules';

  /// One document per member, keyed by phone: which rule they have agreed to,
  /// and at which wording — see `HouseRulesRepository.fetchAcks`.
  static const String collectionHouseRuleAcks = 'house_rule_acks';

  /// A member's own income and spending — nothing to do with the house's
  /// meals or shared expenses. Every document carries `owner_phone` and is
  /// only ever read back filtered by it.
  static const String collectionPersonalTransactions = 'personal_transactions';

  /// A member's private dues with people outside the app — see `DebtEntry`.
  static const String collectionPersonalDebts = 'personal_debts';

  /// The people those dues are kept with, saved on their own so an account
  /// can be opened before any money has moved — see `LedgerPerson`.
  static const String collectionPersonalPeople = 'personal_people';

  /// Categories a member added for themselves, beside the fixed list —
  /// see `CustomCategory`.
  static const String collectionPersonalCategories = 'personal_categories';

  /// How each member arranged their category picker, one document per phone —
  /// see `CategoryOrder`.
  static const String collectionPersonalCategoryOrder =
      'personal_category_order';

  /// The finer cuts a member keeps inside their categories — see
  /// `Subcategory`.
  static const String collectionPersonalSubcategories =
      'personal_subcategories';
  
  static const double appVersion = 1.1;

  /// Where each device records the build it is running, on the member's own
  /// record — what tells an admin who a new-version notice is for.
  static const String fieldAppVersion = 'app_version';
  static const String docBusinessConfig = 'business_config';

  /// The daily meal reminder an admin sets up, on the same
  /// `config/business_config` document the version gate reads. Two fields
  /// rather than one so a house can switch the reminder off without losing
  /// the hour it had settled on.
  static const String fieldReminderEnabled = 'daily_reminder_enabled';

  /// `HH:mm`, 24-hour, in each device's own local time — see
  /// `DailyReminderService`.
  static const String fieldReminderTime = 'daily_reminder_time';

  /// The house's master notification switch, on the same
  /// `config/business_config` document. False silences every notification
  /// the app sends — chat, announcements, bills, the evening reminder, all
  /// of it. A document without the field reads as true, so nothing changes
  /// for a house that has never touched the switch. Checked at send time by
  /// `PushNotificationService` and at the hour by `DailyReminderService`.
  static const String fieldNotificationsEnabled = 'notifications_enabled';

  /// The reminder settings as this device last saw them, as JSON. The headless
  /// job that raises the reminder falls back to it when Firestore cannot be
  /// reached, so a night without a connection still fires at the right hour.
  static const String keyReminderConfig = 'dailyReminderConfig';

  /// The group chat's own identity — its name and its picture, set by an
  /// admin from the thread's settings sheet. Lives under `config` because it
  /// is one document for the whole house, not one per anything.
  static const String docGroupChat = 'group_chat';
}
