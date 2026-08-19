import 'package:get/get.dart';

import '../../../services/connectivity_service.dart';
import '../controller/house_rules_controller.dart';
import '../repository/house_rules_repository.dart';
import '../repository/house_rules_repository_impl.dart';

class HouseRulesBinding extends Bindings {
  @override
  void dependencies() {
    // fenix on both, and lazy: the rules screen is opened long after start-up
    // and its listener should not be running before anyone asks for it, but
    // GetX sweeps plain lazy dependencies when the route that first resolved
    // them is popped.
    Get.lazyPut<HouseRulesRepository>(
      () => HouseRulesRepositoryImpl(
        connectivity: Get.isRegistered<ConnectivityService>()
            ? Get.find<ConnectivityService>()
            : null,
      ),
      fenix: true,
    );
    Get.lazyPut<HouseRulesController>(
      () => HouseRulesController(repository: Get.find<HouseRulesRepository>()),
      fenix: true,
    );
  }
}
