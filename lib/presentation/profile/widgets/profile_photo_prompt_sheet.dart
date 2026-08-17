import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../common/widgets/info_prompt_sheet.dart';
import '../../../common/widgets/profile_avatar.dart';
import '../../../services/member_avatar_service.dart';
import '../../../utils/app_constant.dart';
import '../view/edit_profile_screen.dart';

/// A one-time nudge for members who still have no profile picture — everyone
/// who joined before the sign-up form asked for one, plus anyone who skipped
/// it there.
///
/// Raised from the home screen rather than at sign-in, because it is only on
/// the home screen that the missing picture is visible in context. Closing it
/// without acting is remembered on the device, per account: someone who says
/// no is not asked again.
class ProfilePhotoPrompt {
  const ProfilePhotoPrompt._();

  /// The account already handled this launch. Keyed by phone rather than a
  /// plain flag so signing out and back in as somebody else still asks.
  static String? _handledForPhone;

  /// Shows the sheet when this member has no picture and has not turned the
  /// ask down before. Safe to call on every home-screen build — it decides for
  /// itself whether there is anything to do.
  static Future<void> maybeShow() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String phone = prefs.getString(AppConstant.keyUserPhone) ?? '';
    if (phone.isEmpty) return;

    if (_handledForPhone == phone) return;
    _handledForPhone = phone;

    final String dismissKey = AppConstant.keyProfilePhotoPromptDismissed(phone);
    if (prefs.getBool(dismissKey) ?? false) return;

    if (!Get.isRegistered<MemberAvatarService>()) return;
    final MemberAvatarService directory = Get.find<MemberAvatarService>();
    await directory.load();

    // A read that never landed leaves every picture looking absent — asking
    // for one on the strength of an offline launch would be wrong.
    if (!directory.isLoaded) return;
    if ((directory.myImage ?? '').isNotEmpty) return;

    if (Get.context == null) return;

    final String name = prefs.getString(AppConstant.keyUserName) ?? '';
    final bool? wantsToAdd = await showInfoPromptSheet<bool>(_sheet(name));

    if (wantsToAdd == true) {
      Get.to(() => const EditProfileScreen());
      return;
    }

    // Closed without acting — asked once, and that is the end of it.
    await prefs.setBool(dismissKey, true);
  }

  static Widget _sheet(String name) {
    return Builder(
      builder: (context) {
        final Color primary = Theme.of(context).colorScheme.primary;

        return InfoPromptSheet(
          // The member's own initials, so the sheet is visibly about them
          // rather than a generic banner.
          badge: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 40,
                backgroundColor: primary,
                child: Text(
                  initialsOf(name),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: primary,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 2,
                    ),
                  ),
                  child: const Icon(Icons.camera_alt,
                      size: 15, color: Colors.white),
                ),
              ),
            ],
          ),
          title: 'add_profile_photo_title'.tr,
          message: 'add_profile_photo_message'.tr,
          points: [
            InfoPromptPoint(
                Icons.chat_bubble_outline_rounded, 'photo_benefit_chat'.tr),
            InfoPromptPoint(Icons.groups_outlined, 'photo_benefit_members'.tr),
            InfoPromptPoint(
                Icons.autorenew_rounded, 'photo_benefit_change_anytime'.tr),
          ],
          actionLabel: 'add_photo_now'.tr,
          onAction: () => Get.back(result: true),
          dismissLabel: 'not_now'.tr,
          onDismiss: () => Get.back(result: false),
        );
      },
    );
  }
}
