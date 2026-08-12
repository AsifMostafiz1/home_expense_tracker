import 'package:get/get.dart';
import '../../presentation/auth/binding/auth_binding.dart';
import '../../presentation/meal/binding/meal_binding.dart';
import '../../presentation/expense/binding/expense_binding.dart';
import '../../presentation/member/binding/member_binding.dart';
import '../../presentation/chat/binding/chat_binding.dart';
import '../../presentation/profile/binding/profile_binding.dart';
import '../../presentation/settings/binding/settings_binding.dart';

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    AuthBinding().dependencies();
    MealBinding().dependencies();
    ExpenseBinding().dependencies();
    MemberBinding().dependencies();
    ChatBinding().dependencies();
    ProfileBinding().dependencies();
    SettingsBinding().dependencies();
  }
}
