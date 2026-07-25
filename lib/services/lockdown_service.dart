import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Web-specific implementation is conditionally loaded via a separate file.
// For non-web, we provide no-op stubs.
typedef ViolationCallback = void Function(String reason);

class LockdownService {
  LockdownService._();
  static final LockdownService instance = LockdownService._();

  bool _isLockdownActive = false;
  ViolationCallback? _onViolation;

  // Native bridge to MainActivity.kt. On Android the host sets FLAG_SECURE
  // and stricter SYSTEM_UI_FLAG_IMMERSIVE_STICKY. On every other platform
  // the channel returns MethodNotImplemented which we swallow.
  static const MethodChannel _channel =
      MethodChannel('online_assessment/lockdown');

  bool get isLockdownActive => _isLockdownActive;

  /// Start Kiosk Mode & Anti-Cheat lockdown across all platforms.
  Future<void> enableLockdown({required ViolationCallback onViolation}) async {
    _isLockdownActive = true;
    _onViolation = onViolation;

    // 1. Mobile & Desktop: Immersive sticky mode — hides status bar & quick-access panel
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      );
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    } catch (e) {
      debugPrint('SystemChrome error: $e');
    }

    // 2. Android: ask the Activity to set FLAG_SECURE (blocks screenshots
    //    and the recents-screen thumbnail) and re-apply the immersive flags
    //    natively so the notification shade / Quick Settings can't be pulled.
    if (!kIsWeb) {
      try {
        await _channel.invokeMethod<bool>('enable');
      } catch (e) {
        debugPrint('Lockdown native bridge error (enable): $e');
      }
    }

    // 3. Web: delegate to web-specific implementation
    if (kIsWeb) {
      _enableWebLockdown();
    }
  }

  /// Disable Kiosk Mode and restore normal system UI.
  Future<void> disableLockdown() async {
    _isLockdownActive = false;
    _onViolation = null;

    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
      await SystemChrome.setPreferredOrientations([]);
    } catch (e) {
      debugPrint('SystemChrome restore error: $e');
    }

    if (!kIsWeb) {
      try {
        await _channel.invokeMethod<bool>('disable');
      } catch (e) {
        debugPrint('Lockdown native bridge error (disable): $e');
      }
    }

    if (kIsWeb) {
      _disableWebLockdown();
    }
  }

  void _enableWebLockdown() {
    // Web lockdown is handled by the platform-specific web implementation.
    // On non-web builds this is a no-op.
    _setupWebListeners();
  }

  void _disableWebLockdown() {
    _teardownWebListeners();
  }

  // These are overridden in the web-specific stub via conditional imports.
  // On all non-web platforms they are empty stubs.
  void _setupWebListeners() {}
  void _teardownWebListeners() {}

  void triggerViolation(String reason) {
    if (_isLockdownActive && _onViolation != null) {
      _onViolation!(reason);
    }
  }

  /// Handle App Lifecycle state transitions (mobile/desktop overlay or switch detection).
  void handleLifecycleState(AppLifecycleState state) {
    if (!_isLockdownActive) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      triggerViolation(
        'System overlay, app switch, or notification panel detected!',
      );
    }
  }
}
