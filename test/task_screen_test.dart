import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:demo_project/presentation/task/controller/task_controller.dart';
import 'package:demo_project/presentation/task/model/task_model.dart';
import 'package:demo_project/presentation/task/repository/task_repository.dart';
import 'package:demo_project/presentation/task/view/task_screen.dart';
import 'package:demo_project/presentation/task/widgets/task_check.dart';
import 'package:demo_project/presentation/task/widgets/today_tasks_sheet.dart';
import 'package:demo_project/utils/app_translations.dart';

import 'fake_tasks.dart';

/// `yyyy-MM-dd` for [daysFromNow] days from today, so the fixtures land in
/// the piles the screen sorts by however long from now this runs.
String _day(int daysFromNow) {
  final DateTime now = DateTime.now();
  return TaskModel.keyOf(DateTime(now.year, now.month, now.day + daysFromNow));
}

/// The screens under test, with the controller's stream fed by [fake].
///
/// The controller arms a midnight timer and a reconcile debounce, so it is
/// deleted inside every test rather than in a tear-down: the test binding
/// checks for pending timers before tear-downs run.
Future<FakeTasks> _pump(
  WidgetTester tester,
  List<TaskModel> rows, {
  Widget home = const TaskScreen(),
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues({
    'userPhone': '01711111111',
    'userName': 'Mostafiz',
    ...prefs,
  });

  // A narrow phone: the test font draws every glyph a full square, so this
  // is the width that would overflow first. Tall, so every section of the
  // list is built — a ListView builds only what is on screen.
  tester.view.physicalSize = const Size(360 * 3, 1700 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  Get.testMode = true;
  final FakeTasks fake = FakeTasks(rows);
  Get.put<TaskRepository>(fake);
  Get.put(TaskController(repository: Get.find<TaskRepository>()));

  await tester.pumpWidget(GetMaterialApp(
    translations: AppTranslations(),
    locale: const Locale('en', 'US'),
    home: home,
  ));
  await tester.pumpAndSettle();
  return fake;
}

Future<void> _teardown(WidgetTester tester, FakeTasks fake) async {
  // Fire the reconcile debounce so nothing is left pending, then take the
  // controller down, which cancels the midnight timer.
  await tester.pump(const Duration(milliseconds: 400));
  await Get.delete<TaskController>(force: true);
  await Get.delete<TaskRepository>(force: true);
  fake.dispose();
  Get.reset();
}

void main() {
  final List<TaskModel> rows = [
    TaskModel(
      id: 'bill',
      title: 'Pay the electricity bill',
      date: _day(0),
      hasTime: true,
      timeHour: 23,
      timeMinute: 30,
      reminderMinutes: 60,
      priority: TaskPriority.high,
    ),
    TaskModel(
      id: 'rice',
      title: 'Buy rice for the house before the shop closes',
      date: _day(0),
      done: true,
      doneDate: _day(0),
    ),
    TaskModel(
      id: 'gas',
      title: 'Gas bill',
      date: _day(-2),
      repeat: TaskRepeat.monthly,
    ),
    TaskModel(
      id: 'call',
      title: 'Call the landlord',
      date: _day(1),
      hasTime: true,
      timeHour: 10,
      timeMinute: 0,
    ),
    TaskModel(
      id: 'read',
      title: 'Finish the book',
    ),
  ];

  testWidgets('the list shows the day\'s figure and every pile', (tester) async {
    final FakeTasks fake = await _pump(tester, rows);

    // One of today's two is done.
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('1 of 2 done today'), findsOneWidget);

    // The gas bill is two days late; the tomorrow call and the undated book
    // each sit under their own label.
    expect(find.text('OVERDUE'), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('TOMORROW'), findsOneWidget);
    expect(find.text('SOMEDAY'), findsOneWidget);
    expect(find.text('Gas bill'), findsOneWidget);
    expect(find.text('Move to today'), findsOneWidget);

    // The finished one is on today's list, struck through, not hidden.
    expect(find.text('Buy rice for the house before the shop closes'),
        findsOneWidget);

    expect(tester.takeException(), isNull);
    await _teardown(tester, fake);
  });

  testWidgets('ticking a task writes a completion, a repeating one spawns',
      (tester) async {
    final FakeTasks fake = await _pump(tester, rows);

    // The gas bill repeats monthly: finishing it writes the next one too.
    final Finder gasRow = find.ancestor(
      of: find.text('Gas bill'),
      matching: find.byType(Row),
    );
    await tester.tap(find.descendant(
        of: gasRow.first, matching: find.byType(TaskCheck)));
    await tester.pumpAndSettle();

    expect(fake.writes, ['complete']);
    expect(fake.completed.single.id, 'gas');
    expect(fake.successors.single, isNotNull);
    expect(fake.successors.single!.repeat, TaskRepeat.monthly);
    expect(fake.successors.single!.spawnedFrom, 'gas');
    // The echoed list moved it out of Overdue.
    expect(find.text('OVERDUE'), findsNothing);

    expect(tester.takeException(), isNull);
    await _teardown(tester, fake);
  });

  testWidgets('the done view lists what is finished and can clear it',
      (tester) async {
    final FakeTasks fake = await _pump(tester, rows);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(find.text('Buy rice for the house before the shop closes'),
        findsOneWidget);
    expect(find.text('Pay the electricity bill'), findsNothing);

    expect(tester.takeException(), isNull);
    await _teardown(tester, fake);
  });

  testWidgets('an empty list is a first-run state with a way in', (tester) async {
    final FakeTasks fake = await _pump(tester, const []);

    expect(find.text('No tasks yet'), findsOneWidget);
    expect(find.text('Add your first task'), findsOneWidget);

    // The button opens the editor.
    await tester.tap(find.text('Add your first task'));
    await tester.pumpAndSettle();
    expect(find.text('New task'), findsOneWidget);
    expect(find.text('What needs doing?'), findsOneWidget);

    expect(tester.takeException(), isNull);
    await _teardown(tester, fake);
  });

  testWidgets('the editor refuses an empty title and saves a dated task',
      (tester) async {
    final FakeTasks fake = await _pump(tester, rows);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // The button sits at the bottom of a sheet that scrolls.
    final Finder saveButton = find.widgetWithText(ElevatedButton, 'Add task');
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
    expect(find.text('Give the task a name'), findsOneWidget);
    expect(fake.writes, isEmpty);

    await tester.enterText(find.byType(TextFormField).first, 'Water the plants');
    await tester.ensureVisible(find.text('Tomorrow').last);
    await tester.tap(find.text('Tomorrow').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(fake.writes, ['save']);
    expect(fake.saved.single.title, 'Water the plants');
    expect(fake.saved.single.date, _day(1));
    expect(fake.saved.single.hasTime, isFalse);
    expect(fake.saved.single.reminderMinutes, isNull);

    expect(tester.takeException(), isNull);
    await _teardown(tester, fake);
  });

  testWidgets('the morning sheet lists today and what is left over',
      (tester) async {
    final FakeTasks fake = await _pump(
      tester,
      rows,
      home: const Scaffold(body: SizedBox.expand()),
    );

    // Answers only once the sheet has been closed, so it is held rather
    // than awaited while the sheet is up.
    final Future<TodayTasksPromptResult> result = TodayTasksPrompt.maybeShow();
    await tester.pumpAndSettle();

    expect(find.text("Today's tasks"), findsOneWidget);
    expect(find.text('1 of 2 done today'), findsOneWidget);
    expect(find.text('Gas bill'), findsOneWidget);
    expect(find.text('Pay the electricity bill'), findsOneWidget);
    // Tomorrow's call and the undated book are not the morning's business.
    expect(find.text('Call the landlord'), findsNothing);
    expect(find.text('Finish the book'), findsNothing);
    expect(find.text('1 left over from earlier days'), findsOneWidget);

    // Ticking inside the sheet moves the ring without closing it.
    final Finder billRow = find.ancestor(
      of: find.text('Pay the electricity bill'),
      matching: find.byType(Row),
    );
    await tester.tap(find.descendant(
        of: billRow.first, matching: find.byType(TaskCheck)));
    await tester.pumpAndSettle();
    expect(fake.writes, ['complete']);
    expect(find.text("Today's tasks"), findsOneWidget);
    expect(find.text('2 of 2 done today'), findsOneWidget);

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(await result, TodayTasksPromptResult.shown);

    // A return from the background a moment later is the same visit: the
    // sheet stays away. Opening the app again is a new one: it comes back
    // while anything on today's list is still open.
    expect(await TodayTasksPrompt.maybeShow(onResume: true),
        TodayTasksPromptResult.notNeeded);
    final Future<TodayTasksPromptResult> again = TodayTasksPrompt.maybeShow();
    await tester.pumpAndSettle();
    expect(find.text("Today's tasks"), findsOneWidget);
    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();
    expect(await again, TodayTasksPromptResult.shown);

    expect(tester.takeException(), isNull);
    await _teardown(tester, fake);
  });

  testWidgets('the morning sheet stays quiet on a finished or empty day',
      (tester) async {
    final FakeTasks fake = await _pump(
      tester,
      [
        TaskModel(id: 'a', title: 'Done early', date: _day(0), done: true,
            doneDate: _day(0)),
        TaskModel(id: 'b', title: 'Tomorrow', date: _day(1)),
      ],
      home: const Scaffold(body: SizedBox.expand()),
    );

    expect(await TodayTasksPrompt.maybeShow(), TodayTasksPromptResult.notNeeded);
    await tester.pumpAndSettle();
    expect(find.text("Today's tasks"), findsNothing);

    await _teardown(tester, fake);
  });
}
