import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Visual feedback type — controls the icon color in the toast pill.
enum ToastType { info, success, warning, error }

/// A single toast message to display briefly on screen.
class ToastMessage {
  final String message;
  final IconData? icon;
  final Duration duration;
  final ToastType type;
  final DateTime created;

  ToastMessage({
    required this.message,
    this.icon,
    this.duration = const Duration(seconds: 3),
    this.type = ToastType.info,
  }) : created = DateTime.now();
}

/// Manages a queue of toast messages, showing one at a time.
///
/// Call [show] to enqueue a toast. If no toast is visible the message appears
/// immediately; otherwise it waits until the current toast auto-dismisses.
class ToastNotifier extends StateNotifier<ToastMessage?> {
  ToastNotifier() : super(null);

  Timer? _dismissTimer;
  final _queue = <ToastMessage>[];

  void show(
    String message, {
    IconData? icon,
    Duration? duration,
    ToastType type = ToastType.info,
  }) {
    final toast = ToastMessage(
      message: message,
      icon: icon,
      duration: duration ?? const Duration(seconds: 3),
      type: type,
    );
    if (state != null) {
      _queue.add(toast);
    } else {
      _showToast(toast);
    }
  }

  void _showToast(ToastMessage toast) {
    state = toast;
    _dismissTimer?.cancel();
    _dismissTimer = Timer(toast.duration, () {
      state = null;
      if (_queue.isNotEmpty) {
        _showToast(_queue.removeAt(0));
      }
    });
  }

  /// Dismiss the current toast immediately, advancing to the next in queue.
  void dismiss() {
    _dismissTimer?.cancel();
    state = null;
    if (_queue.isNotEmpty) {
      _showToast(_queue.removeAt(0));
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }
}

final toastProvider =
    StateNotifierProvider<ToastNotifier, ToastMessage?>((ref) => ToastNotifier());
