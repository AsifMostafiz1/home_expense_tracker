import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/profile_controller.dart';
import '../../../common/widgets/custom_button.dart';

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
                _buildTextField(
                  label: 'phone_number'.tr,
                  controller: _phoneController,
                  icon: Icons.phone_outlined,
                  readOnly: true,
                ),
                const SizedBox(height: 24),

                // Name Field
                _buildTextField(
                  label: 'full_name'.tr,
                  controller: _nameController,
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 24),

                // Password Field
                _buildTextField(
                  label: 'password'.tr,
                  controller: _passwordController,
                  icon: Icons.lock_outline,
                  isPassword: true,
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

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    bool isPassword = false,
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Theme.of(context).textTheme.titleSmall?.color?.withOpacity(0.8),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: isPassword,
          readOnly: readOnly,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: readOnly ? Colors.grey.shade600 : Colors.grey.shade400),
            filled: true,
            fillColor: readOnly 
                ? (Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade200)
                : Theme.of(context).cardColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: readOnly ? Colors.transparent : Theme.of(context).colorScheme.primary, 
                width: 1.5
              ),
            ),
          ),
          style: TextStyle(
            color: readOnly ? Colors.grey : null,
          ),
        ),
      ],
    );
  }
}
