import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/profile_controller.dart';
import '../../../common/widgets/avatar_picker.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/custom_text_field.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../utils/app_enums.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final ProfileController _controller = Get.find<ProfileController>();

  @override
  void initState() {
    super.initState();
    // The cached name and phone stand in while the Firestore record is still
    // loading — this screen is reachable from the home-screen photo prompt,
    // which can land seconds after launch.
    _nameController.text = _controller.userModel?.name ?? _controller.userName;
    _phoneController.text =
        _controller.userModel?.phone ?? _controller.userPhone;
    _passwordController.text = ''; // Keep password field empty by default
  }

  @override
  void dispose() {
    // Leaving the screen abandons an unsaved avatar choice — nothing was
    // uploaded yet, the picked file only ever lived in the controller.
    _controller.discardProfileImageChanges();
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  ImageProvider? _avatarImage(ProfileController controller) {
    if (controller.pickedProfileImage != null) {
      return FileImage(controller.pickedProfileImage!);
    }
    if (controller.clearProfileImage) return null;

    final String? url = controller.userModel?.profileImage;
    if (url != null && url.isNotEmpty) return NetworkImage(url);
    return null;
  }

  /// Null while the circle is empty — there is nothing to remove yet.
  VoidCallback? _removeAction(ProfileController controller) =>
      _avatarImage(controller) == null ? null : controller.removeProfileImage;

  void _openPhotoSheet(BuildContext context, ProfileController controller) {
    showPhotoSourceSheet(
      context,
      onPick: controller.pickProfileImage,
      onRemove: _removeAction(controller),
    );
  }

  Widget _buildAvatarPicker(
      BuildContext context, ProfileController controller) {
    return AvatarPicker(
      image: _avatarImage(controller),
      name: controller.userModel?.name ?? controller.userName,
      onPick: controller.pickProfileImage,
      onRemove: _removeAction(controller),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ProfileController>(
      builder: (controller) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back_ios,
                  color: Theme.of(context).textTheme.titleLarge?.color),
              onPressed: () => Get.back(),
            ),
            title: Text(
              'edit_profile'.tr,
              style: TextStyle(
                  color: Theme.of(context).textTheme.titleLarge?.color,
                  fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 8),

                // Avatar — uploaded to Supabase Storage on save, since
                // Firebase Storage is unavailable without project billing.
                _buildAvatarPicker(context, controller),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _openPhotoSheet(context, controller),
                  child: Text('change_photo'.tr),
                ),
                const SizedBox(height: 16),

                // Phone Field (Read Only)
                CustomTextField(
                  labelText: 'phone_number'.tr,
                  hintText: '',
                  controller: _phoneController,
                  prefixIcon: Icons.phone_outlined,
                  readOnly: true,
                ),
                const SizedBox(height: 24),

                // Name Field
                CustomTextField(
                  labelText: 'full_name'.tr,
                  hintText: 'full_name'.tr,
                  controller: _nameController,
                  prefixIcon: Icons.person_outline,
                ),
                const SizedBox(height: 24),

                // Password Field
                CustomTextField(
                  labelText: 'password'.tr,
                  hintText: 'password'.tr,
                  controller: _passwordController,
                  prefixIcon: Icons.lock_outline,
                  obscureText: true,
                ),
                const SizedBox(height: 48),

                // Update Button
                CustomButton(
                  text: 'save_changes'.tr,
                  isLoading: controller.isUpdating,
                  onPressed: () {
                    String name = _nameController.text.trim();

                    if (name.isEmpty) {
                      CustomSnackbar.show(
                          type: SnackbarType.error,
                          message: 'please_fill_all_fields'.tr);
                      return;
                    }

                    // Left blank means "keep the current one" — the controller
                    // simply leaves the field out of the write.
                    controller.updateProfile(
                      name: name,
                      password: _passwordController.text.trim(),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
