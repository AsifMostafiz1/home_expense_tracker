import 'package:get/get.dart';
import '../controller/auth_controller.dart';
import '../repository/auth_repository.dart';
import '../repository/auth_repository_impl.dart';

class AuthBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AuthRepository>(() => AuthRepositoryImpl());
    Get.lazyPut<AuthController>(() => AuthController(repository: Get.find<AuthRepository>()));
  }
}
