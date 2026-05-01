import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../utils/app_enums.dart';

class CustomSnackbar {
  static void show({
    required String message,
    required SnackbarType type,
  }) {
    Color backgroundColor;
    IconData iconData;
    String defaultTitle;

    switch (type) {
      case SnackbarType.success:
        backgroundColor = Colors.green.shade600;
        iconData = Icons.check_circle;
        defaultTitle = 'Success';
        break;
      case SnackbarType.error:
        backgroundColor = Colors.red.shade600;
        iconData = Icons.error;
        defaultTitle = 'Error';
        break;
      case SnackbarType.warning:
        backgroundColor = Colors.orange.shade600;
        iconData = Icons.warning;
        defaultTitle = 'Warning';
        break;
      case SnackbarType.info:
        backgroundColor = Colors.blue.shade600;
        iconData = Icons.info;
        defaultTitle = 'Info';
        break;
    }

    Get.snackbar(
      defaultTitle,
      message,
      snackPosition: SnackPosition.BOTTOM,
      backgroundColor: backgroundColor,
      colorText: Colors.white,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
      icon: Icon(iconData, color: Colors.white),
      duration: const Duration(seconds: 3),
      snackStyle: SnackStyle.FLOATING,
    );
  }
}
