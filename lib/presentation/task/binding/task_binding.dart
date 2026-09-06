import 'package:get/get.dart';

import '../../../services/connectivity_service.dart';
import '../controller/task_controller.dart';
import '../repository/task_repository.dart';
import '../repository/task_repository_impl.dart';

class TaskBinding extends Bindings {
  @override
  void dependencies() {
    // Lazy, so the listener starts the first time something asks — the home
    // screen's morning sheet, or the list itself; fenix, because GetX sweeps
    // plain lazy dependencies when the route that first resolved them is
    // popped, and the reminders are reconciled off this listener.
    Get.lazyPut<TaskRepository>(
      () => TaskRepositoryImpl(
        connectivity: Get.isRegistered<ConnectivityService>()
            ? Get.find<ConnectivityService>()
            : null,
      ),
      fenix: true,
    );
    Get.lazyPut<TaskController>(
      () => TaskController(repository: Get.find<TaskRepository>()),
      fenix: true,
    );
  }
}
