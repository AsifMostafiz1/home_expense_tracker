import '../model/task_model.dart';

abstract class TaskRepository {
  /// Every task [ownerPhone] has, finished ones included, live.
  Stream<List<TaskModel>> watchTasks(String ownerPhone);

  /// Writes [task] — a new document when its id is empty, otherwise the
  /// same one rewritten.
  Future<void> saveTask(TaskModel task);

  /// Marks [task] finished — on [doneDate], the device's own `yyyy-MM-dd` —
  /// and, when it repeats, writes [successor] beside it in the same batch,
  /// so the two land together or not at all.
  Future<void> complete(
    TaskModel task, {
    required String doneDate,
    TaskModel? successor,
  });

  /// Opens [task] again and, when one is named, removes the follow-on copy
  /// that finishing it wrote.
  Future<void> reopen(TaskModel task, {String? successorId});

  Future<void> deleteTask(String id);

  /// Removes every finished task in [ids] at once.
  Future<void> deleteAll(List<String> ids);
}
