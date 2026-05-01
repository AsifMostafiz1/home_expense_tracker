import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../controller/auth_controller.dart';
import '../../../common/widgets/custom_text_field.dart';
import 'sign_up_screen.dart';
import '../binding/auth_binding.dart';

class SignInScreen extends GetView<AuthController> {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              Text(
                'Welcome\nBack',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'Sign in to your account',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 60),
              CustomTextField(
                controller: controller.phoneController,
                hintText: 'Phone Number',
                prefixIcon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
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
                    onPressed:
                        controller.isLoading ? null : () => controller.signIn(),
                    child: controller.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'Sign In',
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
                    Get.to(() => const SignUpScreen(),
                        transition: Transition.rightToLeft,
                        binding: AuthBinding());
                  },
                  child: RichText(
                    text: TextSpan(
                      text: "Don't have an account? ",
                      style: Theme.of(context).textTheme.bodySmall,
                      children: [
                        TextSpan(
                          text: 'Sign Up',
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
