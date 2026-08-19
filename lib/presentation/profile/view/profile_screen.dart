import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/profile_controller.dart';
import '../../../common/widgets/profile_avatar.dart';
import '../../member/view/member_screen.dart';
import '../../monthly_stats/controller/monthly_stats_controller.dart';
import '../../monthly_stats/view/monthly_stats_screen.dart';
import '../../settings/view/settings_screen.dart';
import '../widgets/profile_skeleton.dart';
import 'edit_profile_screen.dart';
import 'edit_history_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ProfileController>(
      builder: (controller) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            title: Text(
              'profile'.tr,
              style: TextStyle(
                color: Theme.of(context).textTheme.titleLarge?.color ?? Colors.black87,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            centerTitle: false,
          ),
          body: controller.isLoading
              ? const ProfileSkeleton()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      // Avatar
                      Center(
                        child: ProfileAvatar(
                          name: controller.userName,
                          phone: controller.userPhone,
                          imageUrl: controller.userModel?.profileImage,
                          isMe: true,
                          size: 100,
                          background: Theme.of(context).colorScheme.primary,
                          foreground: Colors.white,
                          fontSize: 36,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Name with Admin Badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            controller.userName.isNotEmpty ? controller.userName : 'unknown_user'.tr,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).textTheme.titleLarge?.color ?? Colors.black87,
                            ),
                          ),
                          if (controller.isAdminUser) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.verified_user, size: 14, color: Colors.blue.shade700),
                                  const SizedBox(width: 4),
                                  Text(
                                    'admin'.tr,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Phone
                      Text(
                        controller.userPhone,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Stats Row
                      Row(
                        children: [
                          _buildStatCard(
                            context,
                            title: 'meal'.tr,
                            value: '${controller.totalMealsEaten}',
                          ),
                          const SizedBox(width: 12),
                          _buildStatCard(
                            context,
                            title: 'meal_paid'.tr,
                            value: '৳${controller.totalMealExpense.toStringAsFixed(0)}',
                          ),
                          const SizedBox(width: 12),
                          _buildStatCard(
                            context,
                            title: 'other_paid'.tr,
                            value: '৳${controller.totalOtherExpense.toStringAsFixed(0)}',
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),

                      // House Section — open to everyone: what the house pays
                      // and what each member owes is shared information. Only
                      // the actions inside are held back to admins.
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
                            Get.find<MonthlyStatsController>().ensureHistory();
                            Get.to(() => const MonthlyStatsScreen());
                          },
                        ),
                      ),
                      const SizedBox(height: 24),

                      // App Section — app-wide settings, not house data, so
                      // it stands apart. Everyone gets in: which version the
                      // house is meant to run is worth seeing. The screen
                      // itself hands the form to admins only.
                      _buildSectionLabel(context, 'APP'.tr),
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
                          icon: Icons.settings_outlined,
                          title: 'app_version'.tr,
                          subtitle: 'app_version_subtitle'.tr,
                          onTap: () => Get.to(() => const SettingsScreen()),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Account Section
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
                              onTap: () => Get.to(() => const MemberScreen()),
                            ),
                            _buildDivider(context),
                            _buildListTile(
                              context,
                              icon: Icons.history,
                              title: 'edit_history'.tr,
                              onTap: () => Get.to(() => const EditHistoryScreen()),
                            ),
                            _buildDivider(context),
                            _buildListTile(
                              context,
                              icon: Icons.person_outline,
                              title: 'edit_profile'.tr,
                              onTap: () => Get.to(() => const EditProfileScreen()),
                            ),
                            _buildDivider(context),
                            _buildListTile(
                              context,
                              icon: Icons.dark_mode_outlined,
                              title: 'appearance'.tr,
                              onTap: () => _showAppearanceBottomSheet(context, controller),
                            ),
                            _buildDivider(context),
                            _buildListTile(
                              context,
                              icon: Icons.language_outlined,
                              title: 'language'.tr,
                              onTap: () => _showLanguageBottomSheet(context, controller),
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
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Get.back(),
                                        child: Text('cancel'.tr, style: TextStyle(color: Colors.grey.shade700)),
                                      ),
                                      ElevatedButton(
                                        onPressed: () {
                                          Get.back();
                                          controller.logout();
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red.shade50,
                                          foregroundColor: Colors.red,
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
        );
      },
    );
  }

  void _showLanguageBottomSheet(BuildContext context, ProfileController controller) {
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

  void _showAppearanceBottomSheet(BuildContext context, ProfileController controller) {
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
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey,
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        trailing: isSelected 
            ? Icon(Icons.check_circle, color: Theme.of(context).colorScheme.primary) 
            : null,
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, {required String title, required String value}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).textTheme.titleLarge?.color ?? Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
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
          color: textColor ?? (Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87),
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
      trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400, size: 20),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 60, right: 20),
      child: Divider(height: 1, color: Theme.of(context).dividerColor),
    );
  }
}
