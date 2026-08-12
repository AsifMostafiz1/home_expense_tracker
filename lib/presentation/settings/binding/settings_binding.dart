import 'package:get/get.dart';
import '../controller/settings_controller.dart';
import '../repository/settings_repository.dart';
import '../repository/settings_repository_impl.dart';

class SettingsBinding extends Bindings {
  @override
  void dependencies() {
    // fenix on both: GetX sweeps plain lazy dependencies when the route that
    // first resolved them is popped, and this screen is opened long after
    // start-up.
    Get.lazyPut<SettingsRepository>(() => SettingsRepositoryImpl(),
        fenix: true);
    Get.lazyPut<SettingsController>(
      () => SettingsController(repository: Get.find<SettingsRepository>()),
      fenix: true,
    );
  }
}
