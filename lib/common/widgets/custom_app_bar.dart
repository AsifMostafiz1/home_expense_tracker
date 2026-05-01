import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:demo_project/utils/app_constant.dart';
import 'package:demo_project/presentation/auth/view/sign_in_screen.dart';

class CustomAppBar extends StatefulWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? elevation;
  final bool? centerTitle;
  final bool showBackButton;
  final PreferredSizeWidget? bottom;

  const CustomAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.backgroundColor = Colors.white,
    this.foregroundColor = Colors.black87,
    this.elevation = 0,
    this.centerTitle,
    this.showBackButton = true,
    this.bottom,
  });

  @override
  State<CustomAppBar> createState() => _CustomAppBarState();

  @override
  Size get preferredSize => Size.fromHeight(70 + (bottom?.preferredSize.height ?? 0));
}

class _CustomAppBarState extends State<CustomAppBar> {
  String userName = '';
  String userPhone = '';

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      userName = prefs.getString(AppConstant.keyUserName) ?? '';
      userPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
    });
  }

  String getAvatarText(String name) {
    if (name.isEmpty) return 'U';
    List<String> words = name.trim().split(RegExp(r'\s+'));
    String initials = '';
    for (var word in words) {
      if (word.isNotEmpty) {
        initials += word[0].toUpperCase();
      }
      if (initials.length >= 2) break;
    }
    return initials;
  }

  Future<void> _logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Clear all user data
    Get.deleteAll(force: true); // Remove all active controllers (Meal, Dashboard, etc.)
    Get.offAll(() => const SignInScreen());
  }

  @override
  Widget build(BuildContext context) {
    bool canPop = widget.showBackButton && Navigator.canPop(context);

    return AppBar(
      backgroundColor: widget.backgroundColor,
      foregroundColor: widget.foregroundColor,
      elevation: widget.elevation,
      centerTitle: widget.centerTitle ?? false,
      toolbarHeight: 70,
      titleSpacing: canPop ? 0 : 16,
      leadingWidth: canPop ? 56 : 70,
      leading: widget.leading ?? (canPop
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios, size: 20),
                  onPressed: () => Get.back(),
                )
              : Center(
                  child: Container(
                    margin: const EdgeInsets.only(left: 16),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        getAvatarText(userName.isNotEmpty ? userName : (widget.title ?? 'User')),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                )),
      title: widget.titleWidget ?? 
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                userName.isNotEmpty ? userName : (widget.title ?? 'Welcome'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (userPhone.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  userPhone,
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.foregroundColor?.withOpacity(0.6) ?? Colors.black54,
                    fontWeight: FontWeight.normal,
                  ),
                ),
              ]
            ],
          ),
      actions: widget.actions ??
          [
            Container(
              margin: const EdgeInsets.only(right: 16),
              child: IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.logout, color: Colors.red.shade400, size: 20),
                ),
                onPressed: () {
                  Get.dialog(
                    AlertDialog(
                      title: const Text('Logout'),
                      content: const Text('Are you sure you want to logout?'),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      actions: [
                        TextButton(
                          onPressed: () => Get.back(),
                          child: Text(
                            'Cancel',
                            style: TextStyle(color: Colors.grey.shade700),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            Get.back();
                            _logout();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red.shade50,
                            foregroundColor: Colors.red,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text('Logout'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
      bottom: widget.bottom,
    );
  }
}
