import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import '../controller/profile_controller.dart';
import '../../../common/widgets/profile_avatar.dart';
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
    _nameController.text = _controller.userModel?.name ?? '';
    _phoneController.text = _controller.userModel?.phone ?? '';
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

  void _openPhotoSheet(BuildContext context, ProfileController controller) {
    final bool hasPhoto = _avatarImage(controller) != null;

    Get.bottomSheet(
      SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text('take_photo'.tr),
              onTap: () {
                Get.back();
                controller.pickProfileImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('choose_from_gallery'.tr),
              onTap: () {
                Get.back();
                controller.pickProfileImage(ImageSource.gallery);
              },
            ),
            if (hasPhoto)
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(context).colorScheme.error),
                title: Text(
                  'remove_photo'.tr,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                onTap: () {
                  Get.back();
                  controller.removeProfileImage();
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

  Widget _buildAvatarPicker(BuildContext context, ProfileController controller) {
    final ImageProvider? image = _avatarImage(controller);

    return GestureDetector(
      onTap: () => _openPhotoSheet(context, controller),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: Theme.of(context).colorScheme.primary,
            backgroundImage: image,
            child: image == null
                ? Text(
                    initialsOf(controller.userModel?.name ?? controller.userName),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
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
              icon: Icon(Icons.arrow_back_ios, color: Theme.of(context).textTheme.titleLarge?.color),
              onPressed: () => Get.back(),
            ),
            title: Text(
              'edit_profile'.tr,
              style: TextStyle(color: Theme.of(context).textTheme.titleLarge?.color, fontWeight: FontWeight.bold),
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
                    String password = _passwordController.text.trim();
                    
                    if (name.isEmpty) {
                      CustomSnackbar.show(type: SnackbarType.error, message: 'please_fill_all_fields'.tr);
                      return;
                    }
                    
                    // If password is empty, use the existing one
                    String finalPassword = password.isEmpty 
                        ? (controller.userModel?.password ?? '') 
                        : password;

                    controller.updateProfile(
                      name: name,
                      password: finalPassword,
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
