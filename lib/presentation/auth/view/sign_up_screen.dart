import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/services.dart';
import '../../../common/widgets/avatar_picker.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_text_field.dart';
import '../../../common/widgets/custom_button.dart';
import '../controller/auth_controller.dart';

class SignUpScreen extends GetView<AuthController> {
  const SignUpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: const CustomAppBar(),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'create_account'.tr,
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'setup_profile'.tr,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 32),

              // Optional on purpose — a missing picture must never be the
              // reason someone cannot open an account. Whoever skips here is
              // asked once more from the home screen.
              Center(
                child: GetBuilder<AuthController>(
                  builder: (controller) => Column(
                    children: [
                      AvatarPicker(
                        radius: 44,
                        image: controller.pickedProfileImage == null
                            ? null
                            : FileImage(controller.pickedProfileImage!),
                        fallback: const Icon(Icons.person_outline,
                            size: 40, color: Colors.white),
                        onPick: controller.pickProfileImage,
                        onRemove: controller.pickedProfileImage == null
                            ? null
                            : controller.removePickedProfileImage,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'profile_photo_optional'.tr,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              CustomTextField(
                labelText: 'full_name'.tr,
                controller: controller.nameController,
                hintText: 'full_name'.tr,
                prefixIcon: Icons.person_outline,
              ),
              const SizedBox(height: 20),
              CustomTextField(
                labelText: 'phone_number'.tr,
                controller: controller.phoneController,
                hintText: 'phone_number'.tr,
                prefixIcon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
                maxLength: 11,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
              ),
              const SizedBox(height: 20),
              GetBuilder<AuthController>(
                builder: (controller) => CustomTextField(
                  labelText: 'password'.tr,
                  controller: controller.passwordController,
                  hintText: 'password'.tr,
                  prefixIcon: Icons.lock_outline,
                  obscureText: !controller.isPasswordVisible,
                  suffixIcon: IconButton(
                    icon: Icon(
                      controller.isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                      size: 20,
                    ),
                    onPressed: controller.togglePasswordVisibility,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              GetBuilder<AuthController>(
                builder: (controller) => CustomButton(
                  text: 'sign_up'.tr,
                  isLoading: controller.isLoading,
                  onPressed: () => controller.signUp(),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: TextButton(
                  onPressed: () {
                    Get.back();
                  },
                  child: RichText(
                    text: TextSpan(
                      text: 'already_have_account'.tr,
                      style: Theme.of(context).textTheme.bodySmall,
                      children: [
                        TextSpan(
                          text: 'sign_in'.tr,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
