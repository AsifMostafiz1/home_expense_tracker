import 'package:get/get.dart';
import '../../../services/connectivity_service.dart';
import '../controller/chat_controller.dart';
import '../controller/chat_list_controller.dart';
import '../repository/chat_repository.dart';
import '../repository/chat_repository_impl.dart';

class ChatBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<ChatRepository>(
      () => ChatRepositoryImpl(connectivity: Get.find<ConnectivityService>()),
    );
    // The untagged one is the house group. Every direct chat gets its own,
    // tagged with the conversation id and built by the list — see
    // `ChatListController.openDirect`.
    Get.lazyPut(() => ChatController(repository: Get.find<ChatRepository>()));
    Get.lazyPut(
        () => ChatListController(repository: Get.find<ChatRepository>()));
  }
}
