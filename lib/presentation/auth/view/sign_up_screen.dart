import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/services.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_text_field.dart';
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
                'Create\nAccount',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Sign up to get started',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 48),
              CustomTextField(
                controller: controller.nameController,
                hintText: 'Full Name',
                prefixIcon: Icons.person_outline,
              ),
              const SizedBox(height: 20),
              CustomTextField(
                controller: controller.phoneController,
                hintText: 'Phone Number',
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
                  controller: controller.passwordController,
                  hintText: 'Password',
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
                builder: (controller) => SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: controller.isLoading
                        ? null
                        : () => controller.signUp(),
                    child: controller.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'Sign Up',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
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
                      text: "Already have an account? ",
                      style: Theme.of(context).textTheme.bodySmall,
                      children: [
                        TextSpan(
                          text: 'Sign In',
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
