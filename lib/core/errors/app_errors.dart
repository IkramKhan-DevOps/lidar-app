// =============================================================
// USER FEEDBACK HELPERS (Flushbar + Toastification)
// -------------------------------------------------------------
// This file provides two simple helpers to show short user feedback:
// - FlushMessage.flushBar: a compact banner at the top (another_flushbar).
// - Toast.show: a colored toast notification (toastification).
//
// Notes:
// - Logic and behavior are kept exactly as provided.
// - Only explanatory comments were added for better understanding.
// =============================================================

import 'package:another_flushbar/flushbar.dart';
import 'package:flutter/material.dart';
import 'package:toastification/toastification.dart';

class FlushMessage {
  /// Shows a top-positioned Flushbar with a quick tag-based style.
  ///
  /// Parameters:
  /// - context: BuildContext required by Flushbar to display.
  /// - message: The text to display inside the banner.
  /// - tag (optional): Visual style preset. Supported values:
  ///   'success' (default), 'info', 'warning', 'danger'
  ///
  /// Behavior:
  /// - Chooses background color and leading icon based on [tag].
  /// - Auto-dismisses after 3 seconds.
  /// - Appears at the top with margin and rounded corners.
  static Flushbar flushBar(BuildContext context, String message,
      [String tag = 'success']) {
    // Default visuals in case an unknown tag is passed.
    Color color = Colors.black87;
    Icon icon = const Icon(Icons.question_mark_rounded, color: Colors.white);

    // Map known tags to colors and icons.
    switch (tag) {
      case 'danger':
        color = Colors.redAccent;
        icon = const Icon(Icons.error, color: Colors.white);
        break;

      case 'info':
        color = Colors.blueAccent;
        icon = const Icon(Icons.info, color: Colors.white);
        break;

      case 'warning':
        color = Colors.deepOrangeAccent;
        icon = const Icon(Icons.warning, color: Colors.white);
        break;

      case 'success':
        color = Colors.green;
        icon = const Icon(Icons.check_circle, color: Colors.white);
        break;

      default:
      // Keep defaults (black + question mark) for any unknown tag.
        break;
    }

    // Build and immediately show the Flushbar.
    return Flushbar(
      icon: icon, // Leading icon based on the tag
      flushbarPosition: FlushbarPosition.TOP, // Show at the top
      message: message.toString(), // Convert to string defensively
      duration: const Duration(seconds: 3), // Auto-close after 3 seconds
      margin: const EdgeInsets.all(8), // Spacing from screen edges
      borderRadius: BorderRadius.circular(8), // Rounded corners
      backgroundColor: color, // Background based on the tag
    )..show(context); // Trigger display
  }
}

class Toast {
  /// Resolve toastification's type based on a textual tag.
  ///
  /// Supported tags:
  /// - 'success' (default)
  /// - 'info'
  /// - 'warning'
  /// - 'danger' or 'error' -> both map to error style
  static ToastificationType getToastType(String tag) {
    // Default type if tag doesn't match any known case.
    ToastificationType toastType = ToastificationType.success;

    // Map tag to a ToastificationType.
    switch (tag) {
      case 'danger':
      case 'error':
        toastType = ToastificationType.error;
        break;

      case 'info':
        toastType = ToastificationType.info;
        break;

      case 'warning':
        toastType = ToastificationType.warning;
        break;

      case 'success':
        toastType = ToastificationType.success;
        break;

      default:
      // Fallback to success if an unknown tag is provided.
        toastType = ToastificationType.success;
        break;
    }

    return toastType;
  }

  /// Show a toast notification in the top-right corner.
  ///
  /// Parameters:
  /// - context: BuildContext used by the toastification package.
  /// - message: Body text of the toast.
  /// - tag (optional): Visual preset. One of:
  ///   'success' (default), 'info', 'warning', 'danger'/'error'
  /// - heading (optional): Title text shown above the message.
  ///
  /// Visual behavior:
  /// - Uses a filled colored style matching the tag.
  /// - Fades in/out with a short animation.
  /// - Auto-closes after 5 seconds; can be closed by clicking/tapping.
  static void show(BuildContext context, String message,
      [String tag = 'success', heading = 'GR1P Says!']) {
    // Pull current theme colors to match your app's color scheme.
    ColorScheme colors = Theme.of(context).colorScheme;

    toastification.show(
      context: context,
      type: Toast.getToastType(tag), // Map tag -> ToastificationType
      style: ToastificationStyle.fillColored, // Solid, colored background
      autoCloseDuration: const Duration(seconds: 5), // Auto-dismiss timing
      title: Text(
        heading, // Title/heading of the toast
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
      ),
      description: RichText(
        // RichText allows future styling if needed (bold/links/spans).
        text: TextSpan(
          text: message,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: colors.secondary, // Text color for the message
            fontSize: 14,
          ),
        ),
      ),
      alignment: Alignment.topRight, // Position on the screen
      direction: TextDirection.ltr, // Text direction
      animationDuration: const Duration(milliseconds: 300), // Fade timing
      animationBuilder: (context, animation, alignment, child) {
        // Simple fade transition for showing/hiding the toast.
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      showIcon: false, // No leading icon in this design
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      borderRadius: BorderRadius.circular(12), // Rounded corners
      showProgressBar: false, // Hide progress bar under the toast
      closeButtonShowType: CloseButtonShowType.none, // No close 'X' button
      closeOnClick: true, // Clicking the toast closes it
      pauseOnHover: true, // On web/desktop, hovering pauses auto-close
      dragToClose: true, // Allow swipe/drag to close
      applyBlurEffect: true, // Slight blur of content under the toast
      callbacks: ToastificationCallbacks(
        // No-op callbacks; kept for future custom behavior hooks.
        onTap: (toastItem) => () {},
        onCloseButtonTap: (toastItem) {},
        onAutoCompleteCompleted: (toastItem) {},
        onDismissed: (toastItem) => () {},
      ),
    );
  }
}