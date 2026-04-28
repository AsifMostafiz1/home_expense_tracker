import 'package:get/get.dart';
import '../controller/member_controller.dart';

class MemberBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<MemberController>(() => MemberController());
  }
}
