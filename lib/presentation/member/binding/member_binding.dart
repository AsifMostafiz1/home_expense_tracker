import 'package:get/get.dart';
import '../controller/member_controller.dart';
import '../repository/member_repository.dart';
import '../repository/member_repository_impl.dart';

class MemberBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<MemberRepository>(() => MemberRepositoryImpl());
    Get.lazyPut<MemberController>(
        () => MemberController(repository: Get.find<MemberRepository>()));
  }
}
