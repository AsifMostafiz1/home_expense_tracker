import 'package:get/get.dart';
import '../../meal/binding/meal_binding.dart';
import '../../expense/binding/expense_binding.dart';
import '../../member/binding/member_binding.dart';

class DashboardBinding extends Bindings {
  @override
  void dependencies() {
    MealBinding().dependencies();
    ExpenseBinding().dependencies();
    MemberBinding().dependencies();
  }
}
