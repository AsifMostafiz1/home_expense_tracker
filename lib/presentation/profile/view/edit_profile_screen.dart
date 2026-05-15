import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/profile_controller.dart';
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
    _nameController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
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
                const SizedBox(height: 20),
                
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
