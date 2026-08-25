import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/profile_controller.dart';
import '../../member/view/member_screen.dart';
import '../../monthly_stats/controller/monthly_stats_controller.dart';
import '../../monthly_stats/view/monthly_stats_screen.dart';
import '../../house_rules/view/house_rules_screen.dart';
import '../../settings/view/settings_screen.dart';
import '../widgets/profile_header.dart';
import '../widgets/profile_skeleton.dart';
import 'edit_profile_screen.dart';
import 'edit_history_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ScrollController _scroll = ScrollController();

  /// How far the page has been scrolled, in pixels, as far as the header's
  /// own height — everything the header does is placed from this.
  ///
  /// A notifier rather than setState — the header is the only thing that moves
  /// on a scroll frame, and rebuilding the list underneath it sixty times a
  /// second to slide one avatar up would be wasteful.
  final ValueNotifier<double> _offset = ValueNotifier<double>(0);

  /// What the bar gives up between open and closed — the header answers to
  /// this much scroll and no more, since the strip of figures along its
  /// bottom is kept.
  double _travel = 1;

  /// The scroll at which the identity has finished docking. Past it there is
  /// no half-way pose left to tidy up.
  double _dock = 1;

  /// Set while the bar is seeing itself the rest of the way, so the scroll
  /// that causes is not mistaken for the reader's own and answered with
  /// another one.
  bool _settling = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  void _onScroll() {
    _offset.value = _scroll.offset.clamp(0.0, _travel);
  }

  /// Finishes the identity's move once the reader lets go of it.
  ///
  /// An avatar left halfway to the corner is nobody's intention — it is only
  /// where the finger happened to stop. Rather than hold that pose, the page
  /// carries it to whichever end it is nearer, so the identity is ever only
  /// open, docked, or on its way between the two. Past the dock there is
  /// nothing left in mid-move, so the scroll is left exactly where it was.
  bool _settle(ScrollEndNotification notification) {
    if (_settling || notification.depth != 0 || !_scroll.hasClients) {
      return false;
    }

    final double offset = _scroll.offset;
    if (offset <= 0 || offset >= _dock) return false;
    // A page too short to dock the identity has nowhere to settle into;
    // pushing it would only leave the header stuck partway and the list
    // stranded at its end.
    if (_scroll.position.maxScrollExtent < _dock) return false;

    _settling = true;
    final double target = offset < _dock / 2 ? 0 : _dock;
    // Next frame: a scroll cannot be started from inside the notification that
    // reports the last one finishing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) {
        _settling = false;
        return;
      }
      _scroll
          .animateTo(
            target,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() => _settling = false);
    });
    return false;
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _offset.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    final double textScale = MediaQuery.textScalerOf(context).scale(100) / 100;
    _travel = ProfileHeader.travelFor(textScale);
    _dock = ProfileHeader.dockDistance(textScale);

    return GetBuilder<ProfileController>(
      builder: (controller) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: controller.isLoading
              ? const ProfileSkeleton()
              : NotificationListener<ScrollEndNotification>(
                  onNotification: _settle,
                  child: CustomScrollView(
                    controller: _scroll,
                    slivers: [
                      SliverAppBar(
                        pinned: true,
                        expandedHeight:
                            kToolbarHeight + ProfileHeader.heightFor(textScale),
                        // The bar closes down to the toolbar and the strip of
                        // figures under it, not to the toolbar alone: those
                        // three numbers are what the page is for, and they are
                        // wanted at the bottom of it as much as the top.
                        collapsedHeight: kToolbarHeight +
                            ProfileHeader.collapsedFor(textScale),
                        backgroundColor:
                            Theme.of(context).scaffoldBackgroundColor,
                        // Material would otherwise wash the bar with a tint of
                        // the primary colour as it collapses; the page keeps one
                        // background from top to bottom.
                        surfaceTintColor: Colors.transparent,
                        elevation: 0,
                        // The header draws its own hairline at the moment the
                        // cards have finished leaving. A shadow arriving on top
                        // of that would be a second edge in the same place.
                        scrolledUnderElevation: 0,
                        automaticallyImplyLeading: false,
                        // No title and no toolbar row of its own: the header
                        // below owns the whole of the bar, page title included,
                        // because the identity has to move through that space on
                        // its way up.
                        flexibleSpace: ValueListenableBuilder<double>(
                          valueListenable: _offset,
                          builder: (context, offset, _) => ProfileHeader(
                            offset: offset,
                            topPadding: topPadding,
                            name: controller.userName,
                            phone: controller.userPhone,
                            imageUrl: controller.userModel?.profileImage,
                            isAdmin: controller.isAdminUser,
                            mealCount: '${controller.totalMealsEaten}',
                            mealPaid:
                                '৳${controller.totalMealExpense.toStringAsFixed(0)}',
                            otherPaid:
                                '৳${controller.totalOtherExpense.toStringAsFixed(0)}',
                          ),
                        ),
                      ),
                      SliverPadding(
                        // No top inset: the header already carries the gap, so a
                        // reader on a large font scale does not pay for it twice.
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                        sliver: SliverList.list(
                          children: [
                            // House Section — open to everyone: what the house pays
                            // and what each member owes is shared information. Only
                            // the actions inside are held back to admins.
                            //
                            // The member's own ledger used to sit under this in a
                            // section of its own. It has a tab on the home bar now,
                            // and a second door to the same screen one tap deeper
                            // was only ever in the way.
                            _buildSectionLabel(context, 'HOUSE'.tr),
                            const SizedBox(height: 12),
                            Material(
                              color: Theme.of(context).cardColor,
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                    color: Theme.of(context).dividerColor),
                              ),
                              child: _buildListTile(
                                context,
                                icon: Icons.insights_rounded,
                                title: 'monthly_statistics'.tr,
                                subtitle: 'monthly_statistics_subtitle'.tr,
                                // The saved months there carry a figure each; the
                                // launch only worked out this one — see
                                // MonthlyStatsController.ensureHistory.
                                onTap: () {
                                  Get.find<MonthlyStatsController>()
                                      .ensureHistory();
                                  Get.to(() => const MonthlyStatsScreen());
                                },
                              ),
                            ),
                            const SizedBox(height: 24),

                            // Account Section — everything else this member might
                            // want to open, in one list: who else is here, what has
                            // been changed, their own details, the rules they have
                            // agreed to, which version they are on, and how the app
                            // looks. Subtitles are left off throughout; a card that
                            // has some and not others reads as two lists.
                            _buildSectionLabel(context, 'ACCOUNT'.tr),
                            const SizedBox(height: 12),
                            // Material, not a decorated Container: ListTile paints
                            // its ripple on the nearest Material ancestor, so a
                            // colored box in between would hide it.
                            Material(
                              color: Theme.of(context).cardColor,
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                                side: BorderSide(
                                    color: Theme.of(context).dividerColor),
                              ),
                              child: Column(
                                children: [
                                  _buildListTile(
                                    context,
                                    icon: Icons.group_outlined,
                                    title: 'registered_members'.tr,
                                    onTap: () =>
                                        Get.to(() => const MemberScreen()),
                                  ),
                                  _buildDivider(context),
                                  _buildListTile(
                                    context,
                                    icon: Icons.history,
                                    title: 'edit_history'.tr,
                                    onTap: () =>
                                        Get.to(() => const EditHistoryScreen()),
                                  ),
                                  _buildDivider(context),
                                  _buildListTile(
                                    context,
                                    icon: Icons.person_outline,
                                    title: 'edit_profile'.tr,
                                    onTap: () =>
                                        Get.to(() => const EditProfileScreen()),
                                  ),
                                  _buildDivider(context),
                                  _buildListTile(
                                    context,
                                    icon: Icons.gavel_rounded,
                                    title: 'house_rules'.tr,
                                    onTap: () =>
                                        Get.to(() => const HouseRulesScreen()),
                                  ),
                                  _buildDivider(context),
                                  // Everyone gets in: which version the house is
                                  // meant to run, and when the evening reminder
                                  // goes out, are both worth seeing. The screen
                                  // itself hands the forms to admins only.
                                  _buildListTile(
                                    context,
                                    icon: Icons.settings_outlined,
                                    title: 'settings'.tr,
                                    onTap: () =>
                                        Get.to(() => const SettingsScreen()),
                                  ),
                                  _buildDivider(context),
                                  _buildListTile(
                                    context,
                                    icon: Icons.dark_mode_outlined,
                                    title: 'appearance'.tr,
                                    onTap: () => _showAppearanceBottomSheet(
                                        context, controller),
                                  ),
                                  _buildDivider(context),
                                  _buildListTile(
                                    context,
                                    icon: Icons.language_outlined,
                                    title: 'language'.tr,
                                    onTap: () => _showLanguageBottomSheet(
                                        context, controller),
                                  ),
                                  _buildDivider(context),
                                  _buildListTile(
                                    context,
                                    icon: Icons.logout_rounded,
                                    title: 'logout'.tr,
                                    textColor: Colors.red.shade400,
                                    iconColor: Colors.red.shade400,
                                    onTap: () {
                                      Get.dialog(
                                        AlertDialog(
                                          title: Text('logout'.tr),
                                          content: Text('confirm_logout'.tr),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16)),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Get.back(),
                                              child: Text('cancel'.tr,
                                                  style: TextStyle(
                                                      color: Colors
                                                          .grey.shade700)),
                                            ),
                                            ElevatedButton(
                                              onPressed: () {
                                                Get.back();
                                                controller.logout();
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    Colors.red.shade50,
                                                foregroundColor: Colors.red,
                                                elevation: 0,
                                                shape: RoundedRectangleBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8)),
                                              ),
                                              child: Text('logout'.tr),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  void _showLanguageBottomSheet(
      BuildContext context, ProfileController controller) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'language'.tr,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _buildThemeOption(
              context,
              title: 'english'.tr,
              icon: Icons.translate,
              isSelected: controller.currentLanguage == 'en',
              onTap: () {
                controller.changeLanguage('en');
                Get.back();
              },
            ),
            const SizedBox(height: 12),
            _buildThemeOption(
              context,
              title: 'bangla'.tr,
              icon: Icons.translate,
              isSelected: controller.currentLanguage == 'bn',
              onTap: () {
                controller.changeLanguage('bn');
                Get.back();
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  void _showAppearanceBottomSheet(
      BuildContext context, ProfileController controller) {
    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'appearance'.tr,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            _buildThemeOption(
              context,
              title: 'light_mode'.tr,
              icon: Icons.light_mode_outlined,
              isSelected: controller.themeMode == ThemeMode.light,
              onTap: () {
                controller.changeThemeMode(ThemeMode.light);
                Get.back();
              },
            ),
            const SizedBox(height: 12),
            _buildThemeOption(
              context,
              title: 'dark_mode'.tr,
              icon: Icons.dark_mode_outlined,
              isSelected: controller.themeMode == ThemeMode.dark,
              onTap: () {
                controller.changeThemeMode(ThemeMode.dark);
                Get.back();
              },
            ),
            const SizedBox(height: 12),
            _buildThemeOption(
              context,
              title: 'system_default'.tr,
              icon: Icons.settings_brightness_outlined,
              isSelected: controller.themeMode == ThemeMode.system,
              onTap: () {
                controller.changeThemeMode(ThemeMode.system);
                Get.back();
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  Widget _buildThemeOption(
    BuildContext context, {
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected
          ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
          : Theme.of(context).cardColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).dividerColor,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Icon(
          icon,
          color:
              isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        trailing: isSelected
            ? Icon(Icons.check_circle,
                color: Theme.of(context).colorScheme.primary)
            : null,
      ),
    );
  }

  Widget _buildSectionLabel(BuildContext context, String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade500,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildListTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    String? subtitle,
    Color? textColor,
    Color? iconColor,
  }) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: iconColor ?? Colors.grey, size: 24),
      title: Text(
        title,
        style: TextStyle(
          color: textColor ??
              (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87),
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
      trailing:
          Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 60, right: 20),
      child: Divider(height: 1, color: Theme.of(context).dividerColor),
    );
  }
}
