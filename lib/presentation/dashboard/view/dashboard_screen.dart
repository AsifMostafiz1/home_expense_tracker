import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../common/widgets/confirm_dialog.dart';
import '../../../utils/user_session.dart';
import '../../meal/view/meal_screen.dart';
import '../../expense/view/expense_screen.dart';
import '../../chat/view/chat_list_screen.dart';
import '../../personal/view/personal_finance_screen.dart';
import '../../personal/view/personal_report_screen.dart';
import '../../profile/view/profile_screen.dart';
import 'package:get/get.dart';
import '../../profile/controller/profile_controller.dart';
import '../../chat/controller/chat_controller.dart';
import '../../chat/controller/chat_list_controller.dart';
import '../../monthly_stats/controller/monthly_stats_controller.dart';
import '../../monthly_stats/widgets/due_banner.dart';
import '../../../services/home_refresh.dart';
import '../widgets/home_prompts.dart';

class DashboardScreen extends StatefulWidget {
  final int initialIndex;
  const DashboardScreen({super.key, this.initialIndex = 0});

  /// Set while a home screen is mounted — see [selectTab].
  static void Function(int)? _select;

  /// Whether the home screen is up. A tapped notification asks this before it
  /// decides whether to switch tabs or to rebuild the app around one.
  static bool get isOpen => _select != null;

  /// Moves to a tab from outside the widget tree, which is what a notification
  /// tap does. Rebuilding the whole dashboard for this instead would re-run
  /// every binding and every launch prompt under it.
  static void selectTab(int index) => _select?.call(index);

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  late int _selectedIndex;

  /// Whether this home screen was built for a general user. Read once: the
  /// type only ever changes underneath a session from the server, and half a
  /// dashboard swapping its tabs mid-use would be worse than waiting for the
  /// next launch the manage sheet already promises.
  late final bool _isGeneral;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DashboardScreen._select = _selectTab;
    _selectedIndex = widget.initialIndex;
    _isGeneral = UserSession.isGeneral;
    // Pre-load data for other tabs
    Get.find<ProfileController>();
    if (!_isGeneral) {
      // Built here rather than left to the banner's own GetBuilder: whichever
      // widget first resolves a lazy dependency owns it, and would take it
      // down with itself on dispose. It also works out this month's figure,
      // which is what the banner is waiting on. A general user has no banner
      // and no bills, so nothing may resolve the controller for them — its
      // onInit would start reading the house's months.
      Get.find<MonthlyStatsController>();
      // Held, not read: the group thread's controller drives the tab badge
      // and the preview on the chat list, so it has to be listening from
      // launch rather than from the first time somebody opens the thread.
      // A general user has no group thread, so it is never built for them.
      Get.find<ChatController>();
    }
    Get.find<ChatListController>();

    // Setting up the month's meals, the house rules, then the profile
    // picture — see [HomePrompts]. Called off if a tapped notification has
    // taken the reader somewhere by the time the queue gets its turn.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HomePrompts.run(
        isHomeOnTop: () =>
            mounted && (ModalRoute.of(context)?.isCurrent ?? false),
      );
    });
  }

  @override
  void dispose() {
    // Only if it is still ours: a replacement dashboard registers itself
    // before this one is torn down.
    if (DashboardScreen._select == _selectTab) DashboardScreen._select = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _selectTab(int index) {
    if (!mounted || index == _selectedIndex) return;
    setState(() => _selectedIndex = index);
  }

  /// When the app went into the background, or null while it is in front.
  DateTime? _leftAt;

  /// How long the app has to have been away before coming back re-reads the
  /// tab. Long enough that answering a call or copying a code out of the
  /// notification shade costs nothing; short enough that anything the house
  /// did while the phone was in a pocket is on screen by the time it is
  /// looked at.
  static const Duration _staleAfter = Duration(seconds: 30);

  /// Coming back in, two things happen.
  ///
  /// The rules are re-checked every time: the other two asks of the launch
  /// queue belong to a launch — repeating them after every glance at another
  /// app would be nagging — but a rule published while the app sat in the
  /// background has to be agreed to before the house carries on.
  ///
  /// And the tab is re-read, if the app was away long enough to be worth it.
  /// Most of what is on screen is read once and then held — see
  /// [HomeRefresh] — so an app left open on the meal tab overnight would
  /// otherwise still be showing yesterday's figures in the morning.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _leftAt = DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) return;

    HomePrompts.runRulesGate();

    final DateTime? left = _leftAt;
    _leftAt = null;
    if (left == null || DateTime.now().difference(left) < _staleAfter) return;

    // Behind whatever is on screen: every read swaps its data in underneath.
    unawaited(HomeRefresh.tab(_selectedIndex));
  }

  /// The ledger sits after the chat rather than before it, so the index a
  /// notification tap already asks for — 2, the chat — still means the chat.
  ///
  /// The chat tab is the list of conversations now, not a thread: the group
  /// and every direct chat open from it as their own routes, and each marks
  /// itself read while it is on screen.
  ///
  /// A general user gets the personal wallet spread across the same five
  /// slots: their money where the meals were, their dues where the shared
  /// expenses were, direct messages, the report where the combined ledger
  /// was, and the same profile. The chat keeps its slot on purpose — a tapped
  /// message notification still lands on index 2 whichever kind of user
  /// tapped it.
  List<Widget> get _screens => _isGeneral
      ? const <Widget>[
          PersonalFinanceScreen(view: LedgerView.money),
          PersonalFinanceScreen(view: LedgerView.dues),
          ChatListScreen(),
          PersonalReportScreen(),
          ProfileScreen(),
        ]
      : const <Widget>[
          MealScreen(),
          ExpenseScreen(),
          ChatListScreen(),
          PersonalFinanceScreen(),
          ProfileScreen(),
        ];

  void _onItemTapped(int index) => _selectTab(index);

  /// The home screen is the last route on the stack, so the system back
  /// gesture would drop the app straight to the launcher. Held, and answered
  /// here instead: away from the meal tab, back means "back to the meal
  /// tab" — the tabs are not a stack, so the first one stands in for the way
  /// out — and on the meal tab it asks before the app goes anywhere.
  void _handleBack(bool didPop, Object? result) {
    if (didPop || !mounted) return;

    if (_selectedIndex != 0) {
      _selectTab(0);
      return;
    }

    // A held back button fires more than once; without this the second press
    // stacks a duplicate dialog behind the first.
    if (Get.isDialogOpen ?? false) return;

    showConfirmDialog(
      title: 'exit_app'.tr,
      message: 'exit_app_message'.tr,
      confirmText: 'exit'.tr,
      onConfirm: () => SystemNavigator.pop(),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index,
      {int badgeCount = 0}) {
    bool isSelected = _selectedIndex == index;
    final color = isSelected
        ? Theme.of(context).colorScheme.primary
        : Colors.grey.shade400;

    // Expanded rather than a fixed width: five destinations have to share
    // whatever the phone is, and a Bangla label is longer than an English one.
    return Expanded(
      child: GestureDetector(
        onTap: () => _onItemTapped(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 3,
              width: 30,
              decoration: BoxDecoration(
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(3)),
              ),
            ),
            const SizedBox(height: 8),
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  color: color,
                  size: 26,
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -5,
                    top: -5,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : badgeCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _handleBack,
      child: _buildHome(context),
    );
  }

  Widget _buildHome(BuildContext context) {
    final Widget tab = _screens[_selectedIndex];

    return Scaffold(
      // Above every tab's app bar, in the place the offline strip uses. A
      // general user owes no house bill, so their tabs stand alone — wrapping
      // them would also build the controller the banner reads from.
      body: _isGeneral ? tab : DueBanner(child: tab),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: _buildNavRow(),
        ),
      ),
    );
  }

  /// The five destinations for whichever kind of user this is.
  ///
  /// Wrapped in the chat controllers' builders because of the badge: a meal
  /// user's count is the group's unread plus every direct thread's — counted
  /// in two different places — while a general user has no group thread, so
  /// only the direct count is asked for and the group controller is left
  /// unbuilt.
  Widget _buildNavRow() {
    if (_isGeneral) {
      return GetBuilder<ChatListController>(
        builder: (chatList) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavItem(
                  Icons.account_balance_wallet_outlined, 'money_tab'.tr, 0),
              _buildNavItem(Icons.swap_horiz_rounded, 'dues_tab'.tr, 1),
              _buildNavItem(
                Icons.chat_bubble_outline_rounded,
                'chat'.tr,
                2,
                badgeCount: chatList.directUnread,
              ),
              _buildNavItem(Icons.summarize_outlined, 'nav_report'.tr, 3),
              _buildNavItem(Icons.person_outline, 'profile'.tr, 4),
            ],
          );
        },
      );
    }

    return GetBuilder<ChatController>(
      builder: (_) => GetBuilder<ChatListController>(
        builder: (chatList) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildNavItem(Icons.restaurant_outlined, 'meal'.tr, 0),
              _buildNavItem(Icons.receipt_long_outlined, 'expense'.tr, 1),
              _buildNavItem(
                Icons.chat_bubble_outline_rounded,
                'chat'.tr,
                2,
                badgeCount: chatList.totalUnread,
              ),
              _buildNavItem(
                  Icons.account_balance_wallet_outlined, 'nav_personal'.tr, 3),
              _buildNavItem(Icons.person_outline, 'profile'.tr, 4),
            ],
          );
        },
      ),
    );
  }
}
