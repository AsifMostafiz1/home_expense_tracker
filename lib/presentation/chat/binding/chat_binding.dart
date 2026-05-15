import 'package:get/get.dart';
import '../controller/chat_controller.dart';
import '../repository/chat_repository.dart';
import '../repository/chat_repository_impl.dart';

class ChatBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ChatRepository>(() => ChatRepositoryImpl());
    Get.lazyPut(() => ChatController(repository: Get.find<ChatRepository>()));
  }
}
