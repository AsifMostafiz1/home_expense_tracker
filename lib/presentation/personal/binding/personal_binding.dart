import 'package:get/get.dart';

import '../../../services/connectivity_service.dart';
import '../controller/personal_controller.dart';
import '../repository/personal_repository.dart';
import '../repository/personal_repository_impl.dart';

class PersonalBinding extends Bindings {
  @override
  void dependencies() {
    // Lazy, so a member who never opens their own books never starts the two
    // listeners; fenix, because GetX sweeps plain lazy dependencies when the
    // route that first resolved them is popped.
    Get.lazyPut<PersonalRepository>(
      () => PersonalRepositoryImpl(
        connectivity: Get.isRegistered<ConnectivityService>()
            ? Get.find<ConnectivityService>()
            : null,
      ),
      fenix: true,
    );
    Get.lazyPut<PersonalController>(
      () => PersonalController(repository: Get.find<PersonalRepository>()),
      fenix: true,
    );
  }
}
