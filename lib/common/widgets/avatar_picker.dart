import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import 'profile_avatar.dart';

/// Camera / gallery / remove — the one place the app asks where a picture
/// should come from, so registration and the edit screen offer the same menu.
///
/// [onRemove] being null hides the remove entry, which is what a circle with
/// no picture in it wants.
void showPhotoSourceSheet(
  BuildContext context, {
  required void Function(ImageSource source) onPick,
  VoidCallback? onRemove,
}) {
  Get.bottomSheet(
    SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: Text('take_photo'.tr),
            onTap: () {
              Get.back();
              onPick(ImageSource.camera);
            },
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text('choose_from_gallery'.tr),
            onTap: () {
              Get.back();
              onPick(ImageSource.gallery);
            },
          ),
          if (onRemove != null)
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error),
              title: Text(
                'remove_photo'.tr,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () {
                Get.back();
                onRemove();
              },
            ),
        ],
      ),
    ),
    backgroundColor: Theme.of(context).cardColor,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
  );
}

/// Tappable avatar with a camera badge — the control both the sign-up form and
/// the edit-profile screen use to choose a picture.
///
/// Deliberately stateless about *what* is on screen: the caller passes the
/// [image] it wants drawn, because "picked but not saved yet", "already
/// uploaded" and "marked for removal" are decisions its controller owns.
class AvatarPicker extends StatelessWidget {
  /// Drawn inside the circle. Null falls through to [fallback], and then to
  /// the initials of [name].
  final ImageProvider? image;

  final String name;

  /// Shown instead of initials when there is no picture — registration has no
  /// name to work from until it is typed, so it passes an icon.
  final Widget? fallback;

  final double radius;

  final void Function(ImageSource source) onPick;

  /// Null hides "remove photo": there is nothing to remove.
  final VoidCallback? onRemove;

  const AvatarPicker({
    super.key,
    this.image,
    this.name = '',
    this.fallback,
    this.radius = 50,
    required this.onPick,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () =>
          showPhotoSourceSheet(context, onPick: onPick, onRemove: onRemove),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: Theme.of(context).colorScheme.primary,
            backgroundImage: image,
            child: image == null ? (fallback ?? _initials()) : null,
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
              child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _initials() => Text(
        initialsOf(name),
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.72,
          fontWeight: FontWeight.bold,
        ),
      );
}
