import 'dart:async';

import 'package:demo_project/presentation/task/model/task_model.dart';
import 'package:demo_project/presentation/task/repository/task_repository.dart';

/// The task list with no Firestore behind it — one stream the screen reads,
/// and a record of every write it asked for.
class FakeTasks implements TaskRepository {
  final StreamController<List<TaskModel>> _stream =
      StreamController<List<TaskModel>>.broadcast();

  List<TaskModel> rows;

  /// What the screen wrote, in order: 'save', 'complete', 'reopen',
  /// 'delete', 'deleteAll'.
  final List<String> writes = [];
  final List<TaskModel> completed = [];
  final List<TaskModel?> successors = [];
  final List<TaskModel> saved = [];

  FakeTasks(this.rows);

  @override
  Stream<List<TaskModel>> watchTasks(String ownerPhone) async* {
    yield rows;
    yield* _stream.stream;
  }

  /// Pushes a new list down the stream, the way a Firestore snapshot would.
  void emit(List<TaskModel> next) {
    rows = next;
    _stream.add(next);
  }

  @override
  Future<void> saveTask(TaskModel task) async {
    writes.add('save');
    saved.add(task);
  }

  @override
  Future<void> complete(
    TaskModel task, {
    required String doneDate,
    TaskModel? successor,
  }) async {
    writes.add('complete');
    completed.add(task);
    successors.add(successor);
    // Echo the way Firestore's local store would.
    emit([
      for (final TaskModel t in rows)
        if (t.id == task.id)
          t.copyWith(done: true, doneDate: doneDate)
        else
          t,
      if (successor != null) successor.copyWith(id: 'spawned_${task.id}'),
    ]);
  }

  @override
  Future<void> reopen(TaskModel task, {String? successorId}) async {
    writes.add('reopen');
    emit([
      for (final TaskModel t in rows)
        if (t.id == task.id)
          t.copyWith(done: false, clearDoneAt: true)
        else if (t.id != successorId)
          t,
    ]);
  }

  @override
  Future<void> deleteTask(String id) async {
    writes.add('delete');
    emit(rows.where((t) => t.id != id).toList());
  }

  @override
  Future<void> deleteAll(List<String> ids) async {
    writes.add('deleteAll');
    emit(rows.where((t) => !ids.contains(t.id)).toList());
  }

  void dispose() => _stream.close();
}
