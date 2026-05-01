import 'package:get/get.dart';
import '../../presentation/auth/binding/auth_binding.dart';
import '../../presentation/meal/binding/meal_binding.dart';
import '../../presentation/expense/binding/expense_binding.dart';
import '../../presentation/member/binding/member_binding.dart';

class InitialBinding extends Bindings {
  @override
  void dependencies() {
    AuthBinding().dependencies();
    MealBinding().dependencies();
    ExpenseBinding().dependencies();
    MemberBinding().dependencies();
  }
}
