import 'package:flutter/material.dart';
import '../../constants/app_constants.dart';

enum StateType { 
  loading, 
  empty, 
  error, 
  authRequired,
  custom 
}

class StateDisplayWidget extends StatelessWidget {
  final StateType type;
  final IconData? icon;
  final String title;
  final String? subtitle;
  final String? buttonText;
  final VoidCallback? onAction;
  final String? secondaryButtonText;
  final VoidCallback? onSecondaryAction;
  final Widget? customContent;

  const StateDisplayWidget({
    super.key,
    required this.type,
    required this.title,
    this.icon,
    this.subtitle,
    this.buttonText,
    this.onAction,
    this.secondaryButtonText,
    this.onSecondaryAction,
    this.customContent,
  });

  factory StateDisplayWidget.empty({
    required String title,
    String? subtitle,
    IconData? icon,
    String? buttonText,
    VoidCallback? onAction,
  }) {
    return StateDisplayWidget(
      type: StateType.empty,
      icon: icon ?? Icons.music_note_outlined,
      title: title,
      subtitle: subtitle,
      buttonText: buttonText ?? 'Refresh',
      onAction: onAction,
    );
  }

  factory StateDisplayWidget.error({
    required String title,
    required String error,
    IconData? icon,
    String? buttonText,
    VoidCallback? onAction,
    String? secondaryButtonText,
    VoidCallback? onSecondaryAction,
  }) {
    return StateDisplayWidget(
      type: StateType.error,
      icon: icon ?? Icons.error_outline,
      title: title,
      subtitle: error,
      buttonText: buttonText ?? 'Retry',
      onAction: onAction,
      secondaryButtonText: secondaryButtonText,
      onSecondaryAction: onSecondaryAction,
    );
  }

  factory StateDisplayWidget.authRequired({
    String? title,
    String? subtitle,
    String? buttonText,
    VoidCallback? onAction,
    String? secondaryButtonText,
    VoidCallback? onSecondaryAction,
  }) {
    return StateDisplayWidget(
      type: StateType.authRequired,
      icon: Icons.lock_outline,
      title: title ?? 'Authentication Required',
      subtitle: subtitle ?? 'Please log in to continue',
      buttonText: buttonText ?? 'Login',
      onAction: onAction,
      secondaryButtonText: secondaryButtonText ?? 'Retry',
      onSecondaryAction: onSecondaryAction,
    );
  }

  factory StateDisplayWidget.loading({
    String? title,
  }) {
    return StateDisplayWidget(
      type: StateType.loading,
      title: title ?? 'Loading...',
      customContent: const CircularProgressIndicator(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppConstants.defaultPadding * 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (customContent != null) 
              customContent!
            else if (icon != null)
              Icon(
                icon,
                size: 64,
                color: Colors.grey,
              ),
            
            if (icon != null || customContent != null)
              const SizedBox(height: AppConstants.defaultPadding),
            
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            
            if (subtitle != null) ...[
              const SizedBox(height: AppConstants.smallPadding),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey,
                ),
              ),
            ],
            
            if (buttonText != null && onAction != null) ...[
              const SizedBox(height: AppConstants.defaultPadding),
              ElevatedButton(
                onPressed: onAction,
                child: Text(buttonText!),
              ),
            ],
            
            if (secondaryButtonText != null && onSecondaryAction != null) ...[
              const SizedBox(height: AppConstants.smallPadding),
              TextButton(
                onPressed: onSecondaryAction,
                child: Text(secondaryButtonText!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}