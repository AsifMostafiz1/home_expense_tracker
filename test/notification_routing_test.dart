import 'package:flutter_test/flutter_test.dart';

import 'package:demo_project/services/notification_router.dart';

/// Every `type` the app puts on a notification, and where a tap on it should
/// land. Adding a sender means adding a line here — a notification that opens
/// nothing in particular is the bug this guards against.
const Map<String, NotificationDestination> _senders = {
  // chat_controller._planPush / _notifyReaction — the house thread
  'chat_message': NotificationDestination.groupThread,
  // chat_controller._directPushData — one member to another
  'direct_message': NotificationDestination.directThread,
  // meal_controller.submitAnnouncement
  'announcement': NotificationDestination.meals,
  // meal_controller._updateOtherUserMeal
  'meal': NotificationDestination.meals,
  // daily_reminder_service._notify — the evening summary
  'meal_reminder': NotificationDestination.meals,
  // expense_controller — an admin edited or deleted somebody's expense
  'expense': NotificationDestination.expenses,
  // house_rules_controller._notifyHouse
  'house_rules': NotificationDestination.houseRules,
  // monthly_stats_controller — the month's bill, per member and house-wide
  'monthly_bill': NotificationDestination.monthlyBill,
  // member_controller.setAdminRole
  'role': NotificationDestination.profile,
  // member_controller.removeMember
  'account_removed': NotificationDestination.signedOut,
  // task_reminder_service — an alarm the member set on their own task
  'task_reminder': NotificationDestination.tasks,
};

void main() {
  test('every notification the app sends has somewhere to go', () {
    _senders.forEach((type, expected) {
      expect(
        NotificationRouter.destinationFor(type),
        expected,
        reason: 'a "$type" notification lands in the wrong place',
      );
    });
  });

  test('destinations point at the tab that holds them', () {
    // Matches `DashboardScreen._screens`: meal, expense, chat, ledger,
    // profile.
    expect(NotificationDestination.meals.tab, 0);
    expect(NotificationDestination.expenses.tab, 1);
    expect(NotificationDestination.groupThread.tab, 2);
    expect(NotificationDestination.directThread.tab, 2);
    expect(NotificationDestination.houseRules.tab, 4);
    expect(NotificationDestination.monthlyBill.tab, 4);
    expect(NotificationDestination.profile.tab, 4);
    expect(NotificationDestination.tasks.tab, 4);

    // Not a tab at all — the session is over.
    expect(NotificationDestination.signedOut.tab, -1);
  });

  test('a notification this build does not know still opens the app', () {
    // An older build's payload, or one with nothing on it at all.
    expect(NotificationRouter.destinationFor(null),
        NotificationDestination.meals);
    expect(NotificationRouter.destinationFor(''),
        NotificationDestination.meals);
    expect(NotificationRouter.destinationFor('something_new'),
        NotificationDestination.meals);
  });
}
