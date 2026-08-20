import 'package:flutter/material.dart';
import '../../meal/view/meal_screen.dart';
import '../../expense/view/expense_screen.dart';
import '../../chat/view/chat_screen.dart';
import '../../personal/view/personal_finance_screen.dart';
import '../../profile/view/profile_screen.dart';
import 'package:get/get.dart';
import '../../profile/controller/profile_controller.dart';
import '../../chat/controller/chat_controller.dart';
import '../../monthly_stats/controller/monthly_stats_controller.dart';
import '../../monthly_stats/widgets/due_banner.dart';
import '../widgets/home_prompts.dart';

class DashboardScreen extends StatefulWidget {
  final int initialIndex;
  const DashboardScreen({super.key, this.initialIndex = 0});

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
    _selectedIndex = widget.initialIndex;
    // Pre-load data for other tabs
    Get.find<ProfileController>();
    // Built here rather than left to the banner's own GetBuilder: whichever
    // widget first resolves a lazy dependency owns it, and would take it down
    // with itself on dispose. It also works out this month's figure, which is
    // what the banner is waiting on.
    Get.find<MonthlyStatsController>();
    final chatController = Get.find<ChatController>();
    chatController.setChatScreenVisible(_selectedIndex == 2);

    // Setting up the month's meals, the house rules, then the profile
    // picture — see [HomePrompts].
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HomePrompts.run();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
  static const List<Widget> _screens = <Widget>[
    MealScreen(),
    ExpenseScreen(),
    ChatScreen(),
    PersonalFinanceScreen(),
    ProfileScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    Get.find<ChatController>().setChatScreenVisible(index == 2);
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
          child: GetBuilder<ChatController>(
            builder: (chatController) {
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
                    badgeCount: chatController.unseenCount
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
    );
  }
}
