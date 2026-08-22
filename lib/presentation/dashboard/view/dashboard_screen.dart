import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../common/widgets/confirm_dialog.dart';
import '../../meal/view/meal_screen.dart';
import '../../expense/view/expense_screen.dart';
import '../../chat/view/chat_list_screen.dart';
import '../../personal/view/personal_finance_screen.dart';
import '../../profile/view/profile_screen.dart';
import 'package:get/get.dart';
import '../../profile/controller/profile_controller.dart';
import '../../chat/controller/chat_controller.dart';
import '../../chat/controller/chat_list_controller.dart';
import '../../monthly_stats/controller/monthly_stats_controller.dart';
import '../../monthly_stats/widgets/due_banner.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    DashboardScreen._select = _selectTab;
    _selectedIndex = widget.initialIndex;
    // Pre-load data for other tabs
    Get.find<ProfileController>();
    // Built here rather than left to the banner's own GetBuilder: whichever
    // widget first resolves a lazy dependency owns it, and would take it down
    // with itself on dispose. It also works out this month's figure, which is
    // what the banner is waiting on.
    Get.find<MonthlyStatsController>();
    // Held, not read: the group thread's controller drives the tab badge and
    // the preview on the chat list, so it has to be listening from launch
    // rather than from the first time somebody opens the thread.
    Get.find<ChatController>();
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

  /// Only the rules are re-checked on the way back in. The other two asks
  /// belong to a launch — repeating them after every glance at another app
  /// would be nagging — but a rule published while the app sat in the
  /// background has to be agreed to before the house carries on.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) HomePrompts.runRulesGate();
  }

  /// The ledger sits after the chat rather than before it, so the index a
  /// notification tap already asks for — 2, the chat — still means the chat.
  ///
  /// The chat tab is the list of conversations now, not a thread: the group
  /// and every direct chat open from it as their own routes, and each marks
  /// itself read while it is on screen.
  static const List<Widget> _screens = <Widget>[
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


  Widget _buildNavItem(IconData icon, String label, int index, {int badgeCount = 0}) {
    bool isSelected = _selectedIndex == index;
    final color = isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade400;

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
                color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(3)),
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
    return Scaffold(
      // Above every tab's app bar, in the place the offline strip uses.
      body: DueBanner(child: _screens[_selectedIndex]),
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
          // Both, because the number on the tab is the group's unread plus
          // every direct thread's — and the two are counted in different
          // places.
          child: GetBuilder<ChatController>(
            builder: (_) => GetBuilder<ChatListController>(
              builder: (chatList) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildNavItem(Icons.restaurant_outlined, 'meal'.tr, 0),
                    _buildNavItem(
                        Icons.receipt_long_outlined, 'expense'.tr, 1),
                    _buildNavItem(
                      Icons.chat_bubble_outline_rounded,
                      'chat'.tr,
                      2,
                      badgeCount: chatList.totalUnread,
                    ),
                    _buildNavItem(Icons.account_balance_wallet_outlined,
                        'nav_personal'.tr, 3),
                    _buildNavItem(Icons.person_outline, 'profile'.tr, 4),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
