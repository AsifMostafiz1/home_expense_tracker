import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../presentation/expense/controller/expense_controller.dart';
import '../presentation/meal/controller/meal_controller.dart';
import '../presentation/monthly_stats/controller/monthly_stats_controller.dart';
import '../presentation/profile/controller/profile_controller.dart';

/// Re-reads what a home tab is showing.
///
/// Not every tab is live. The chat and the chat list run off Firestore
/// listeners, as do the announcements and the personal ledger, and are current
/// by the time anybody looks at them. The meal figures, the expense list and
/// the profile are each read once and then held — which is right for a tab
/// somebody opens and reads, and wrong the moment something outside the app
/// says those figures have changed.
///
/// Two things say exactly that, and both land here:
///
///   • a tapped notification — see `NotificationRouter`;
///   • coming back to an app that was left open, which may have been a minute
///     ago or a fortnight.
///
/// Every read is the background kind, the same one the tab's own
/// pull-to-refresh runs, so data is swapped in underneath rather than the
/// screen being blanked and rebuilt while somebody is looking at it.
class HomeRefresh {
  const HomeRefresh._();

  /// When each tab was last read through here.
  static final Map<int, DateTime> _lastRun = <int, DateTime>{};

  /// How close together two asks for the same tab have to be before the second
  /// is taken as already answered. Tapping a notification does both of the
  /// things above at once — it resumes the app and then changes tab — so the
  /// two arrive within a moment of each other, and the second would be paying
  /// for a read the first has just made.
  static const Duration _justRead = Duration(seconds: 5);

  /// Everything the tab at [index] shows, read again. Indices are the
  /// dashboard's — see `DashboardScreen._screens`.
  ///
  /// Failures are swallowed: this runs behind whatever the user was doing, and
  /// a figure that could not be refreshed is a worse screen, not a broken one.
  static Future<void> tab(int index) async {
    final DateTime now = DateTime.now();
    final DateTime? last = _lastRun[index];
    if (last != null && now.difference(last) < _justRead) return;
    _lastRun[index] = now;

    try {
      switch (index) {
        case 0: // Meals. The announcements above them are live already.
          final MealController? meals = _live<MealController>();
          if (meals != null) {
            await meals.fetchMeals(background: true);
            await meals.fetchMonthlyStats(background: true);
          }
          break;

        case 1: // Expenses.
          await _live<ExpenseController>()?.fetchExpenses(background: true);
          break;

        case 4: // The account, the role badge and the lifetime figures.
          await _live<ProfileController>()?.refreshProfile();
          break;

        // The chat and the personal ledger are both live.
        default:
          break;
      }

      // The reminder strip sits above every tab and is fed by a controller
      // none of them own, so it is refreshed whichever tab this was.
      await MonthlyStatsController.refreshDuesIfLoaded();
    } catch (e) {
      debugPrint('HomeRefresh: could not refresh tab $index — $e');
    }
  }

  /// A controller that is registered *and* already built.
  ///
  /// `isRegistered` on its own is true for a lazy registration nobody has
  /// resolved yet, and resolving one here would build it — whose own `onInit`
  /// reads everything anyway, so there would be nothing to refresh and a
  /// duplicate read to pay for.
  static T? _live<T>() {
    if (!Get.isRegistered<T>() || Get.isPrepared<T>()) return null;
    return Get.find<T>();
  }
}
