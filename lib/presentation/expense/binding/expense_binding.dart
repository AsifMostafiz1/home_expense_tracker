import 'package:get/get.dart';
import '../../../services/connectivity_service.dart';
import '../controller/expense_controller.dart';
import '../repository/expense_repository.dart';
import '../repository/expense_repository_impl.dart';

class ExpenseBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ExpenseRepository>(
      () =>
          ExpenseRepositoryImpl(connectivity: Get.find<ConnectivityService>()),
    );
    Get.lazyPut<ExpenseController>(
        () => ExpenseController(repository: Get.find<ExpenseRepository>()));
  }
}
