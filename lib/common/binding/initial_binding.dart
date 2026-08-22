import 'package:get/get.dart';
import '../../services/chat_outbox_service.dart';
import '../../services/connectivity_service.dart';
import '../../services/member_avatar_service.dart';
import '../../services/presence_service.dart';
import '../../services/push_outbox_service.dart';
import '../../services/receipt_outbox_service.dart';
import '../../presentation/auth/binding/auth_binding.dart';
import '../../presentation/meal/binding/meal_binding.dart';
import '../../presentation/expense/binding/expense_binding.dart';
import '../../presentation/member/binding/member_binding.dart';
import '../../presentation/chat/binding/chat_binding.dart';
import '../../presentation/profile/binding/profile_binding.dart';
import '../../presentation/monthly_stats/binding/monthly_stats_binding.dart';
import '../../presentation/settings/binding/settings_binding.dart';
import '../../presentation/house_rules/binding/house_rules_binding.dart';
import '../../presentation/personal/binding/personal_binding.dart';

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    // Permanent, and ahead of everything else: the expense repository reads
    // the connection flag on every write, and the outbox flushes itself when
    // the connection comes back. Neither may vanish with a route.
    final ConnectivityService connectivity =
        Get.put(ConnectivityService(), permanent: true);
    connectivity.init();
    Get.put(ReceiptOutboxService(), permanent: true).init(connectivity);
    Get.put(ChatOutboxService(connectivity: connectivity), permanent: true)
        .init(connectivity);
    Get.put(PushOutboxService(connectivity: connectivity), permanent: true)
        .init(connectivity);

    // Registered before the feature bindings, and permanent: every screen's
    // avatars resolve against it, so it has to outlive the controller that
    // happens to be on screen.
    Get.put(MemberAvatarService(), permanent: true).load();

    // Who is around right now — one field on the member's own user document,
    // stamped while the app is in front. The chat list reads it back through
    // the member stream it already holds.
    Get.put(PresenceService(), permanent: true).init();

    AuthBinding().dependencies();
    MealBinding().dependencies();
    ExpenseBinding().dependencies();
    MemberBinding().dependencies();
    ChatBinding().dependencies();
    ProfileBinding().dependencies();
    MonthlyStatsBinding().dependencies();
    SettingsBinding().dependencies();
    HouseRulesBinding().dependencies();
    PersonalBinding().dependencies();
  }
}
