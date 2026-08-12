import 'package:get/get.dart';
import '../controller/settings_controller.dart';
import '../repository/settings_repository.dart';
import '../repository/settings_repository_impl.dart';

class SettingsBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SettingsRepository>(() => SettingsRepositoryImpl());
    Get.lazyPut<SettingsController>(
        () => SettingsController(repository: Get.find<SettingsRepository>()));
  }
}
