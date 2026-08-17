import 'package:get/get.dart';
import '../../services/member_avatar_service.dart';
import '../../presentation/auth/binding/auth_binding.dart';
import '../../presentation/meal/binding/meal_binding.dart';
import '../../presentation/expense/binding/expense_binding.dart';
import '../../presentation/member/binding/member_binding.dart';
import '../../presentation/chat/binding/chat_binding.dart';
import '../../presentation/profile/binding/profile_binding.dart';
import '../../presentation/monthly_stats/binding/monthly_stats_binding.dart';
import '../../presentation/settings/binding/settings_binding.dart';

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    // Registered first, and permanent: every screen's avatars resolve against
    // it, so it has to outlive the controller that happens to be on screen.
    Get.put(MemberAvatarService(), permanent: true).load();

    AuthBinding().dependencies();
    MealBinding().dependencies();
    ExpenseBinding().dependencies();
    MemberBinding().dependencies();
    ChatBinding().dependencies();
    ProfileBinding().dependencies();
    MonthlyStatsBinding().dependencies();
    SettingsBinding().dependencies();
  }
}
