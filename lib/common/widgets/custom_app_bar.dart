import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String? title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final double? elevation;
  final bool centerTitle;
  final bool showBackButton;
  final PreferredSizeWidget? bottom;

  const CustomAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.leading,
    this.backgroundColor,
    this.foregroundColor,
    this.elevation = 0,
    this.centerTitle = true,
    this.showBackButton = true,
    this.bottom,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    bool canPop = showBackButton && Navigator.canPop(context);
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    
    final effectiveBgColor = backgroundColor ?? Theme.of(context).cardColor;
    final effectiveFgColor = foregroundColor ?? Theme.of(context).textTheme.titleLarge?.color ?? (isDark ? Colors.white : Colors.black87);

    return Container(
      decoration: BoxDecoration(
        color: effectiveBgColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: effectiveFgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        centerTitle: centerTitle,
        toolbarHeight: kToolbarHeight,
        titleSpacing: canPop ? 0 : 16,
        leadingWidth: canPop ? 56 : 0,
        leading: leading ??
            (canPop
                ? IconButton(
                    icon: const Icon(Icons.arrow_back_ios, size: 20),
                    // Not Get.back(): it only closes a visible snackbar and
                    // returns, leaving the user stuck on the page.
                    onPressed: () => Navigator.of(context).maybePop(),
                  )
                : const SizedBox.shrink()),
        title: titleWidget ??
            Text(
              title ?? '',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: effectiveFgColor,
                letterSpacing: -0.5,
              ),
            ),
        actions: actions ?? [const SizedBox(width: 16)], // Empty spacing if no actions
        bottom: bottom,
      ),
    );
  }
}
