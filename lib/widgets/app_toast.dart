import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

void showAppToast(BuildContext context, String message, {bool isError = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(message, maxLines: 1, overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
    backgroundColor: isError ? AppColors.danger : AppColors.surface,
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 2),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: isError ? AppColors.danger : AppColors.primary),
    ),
  ));
}
