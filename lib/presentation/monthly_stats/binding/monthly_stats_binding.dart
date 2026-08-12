import 'package:get/get.dart';
import '../../meal/repository/meal_repository.dart';
import '../../meal/repository/meal_repository_impl.dart';
import '../controller/month_details_controller.dart';
import '../controller/monthly_stats_controller.dart';
import '../repository/monthly_stats_repository.dart';
import '../repository/monthly_stats_repository_impl.dart';

class MonthlyStatsBinding extends Bindings {
  @override
  void dependencies() {
    // fenix: GetX sweeps a plain `lazyPut` dependency once the route that
    // first resolved it is popped. The controllers survive that — they are
    // GetxServices holding their own reference — but a *later* lookup does
    // not, and the month details controller is built on the first tap, long
    // after the statistics route has come and gone. fenix lets the builder
    // bring the instance back instead of throwing "not found".
    Get.lazyPut<MonthlyStatsRepository>(() => MonthlyStatsRepositoryImpl(),
        fenix: true);
    Get.lazyPut<MonthlyStatsController>(
      () => MonthlyStatsController(
        repository: Get.find<MonthlyStatsRepository>(),
        mealRepository: _mealRepository(),
      ),
      fenix: true,
    );

    Get.lazyPut<MonthDetailsController>(
      () => MonthDetailsController(
        mealRepository: _mealRepository(),
        statsRepository: Get.find<MonthlyStatsRepository>(),
      ),
      fenix: true,
    );
  }

  /// The meal feature owns this one, and registers it without fenix. Building
  /// a fresh instance when it has been swept away costs nothing — these
  /// repositories are stateless wrappers around Firestore.
  MealRepository _mealRepository() => Get.isRegistered<MealRepository>()
      ? Get.find<MealRepository>()
      : MealRepositoryImpl();
}
