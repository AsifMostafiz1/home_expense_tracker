import 'package:get/get.dart';
import '../controller/meal_controller.dart';
import '../repository/meal_repository.dart';
import '../repository/meal_repository_impl.dart';

class MealBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<MealRepository>(() => MealRepositoryImpl());
    Get.lazyPut<MealController>(
        () => MealController(repository: Get.find<MealRepository>()));
  }
}
