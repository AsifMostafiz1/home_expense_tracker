import 'package:get/get.dart';
import '../controller/expense_controller.dart';
import '../repository/expense_repository.dart';
import '../repository/expense_repository_impl.dart';

class ExpenseBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ExpenseRepository>(() => ExpenseRepositoryImpl());
    Get.lazyPut<ExpenseController>(
        () => ExpenseController(repository: Get.find<ExpenseRepository>()));
  }
}
