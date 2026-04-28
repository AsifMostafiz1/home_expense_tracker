import 'package:get/get.dart';

class MealController extends GetxController {
  final Rx<DateTime> focusedDay = DateTime.now().obs;
  final Rx<DateTime?> selectedDay = DateTime.now().obs;

  late final DateTime firstDay;
  late final DateTime lastDay;

  @override
  void onInit() {
    super.onInit();
    final DateTime today = DateTime.now();
    // Previous 3 months and current month
    firstDay = DateTime(today.year, today.month - 3, 1);
    lastDay = DateTime(today.year, today.month + 1, 0); // End of current month
  }

  void onDaySelected(DateTime selected, DateTime focused) {
    selectedDay.value = selected;
    focusedDay.value = focused;
  }
  
  void onPageChanged(DateTime focused) {
    focusedDay.value = focused;
  }

  int getMealCount(DateTime date) {
    // Friday count 2, other days count 1
    return date.weekday == DateTime.friday ? 2 : 1;
  }
}
