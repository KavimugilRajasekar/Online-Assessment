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

  // Debounce: ignore violations that fire within this window of each other.
  // Prevents the overlay itself (which causes a brief lifecycle pause on
  // some devices) from generating a second violation immediately.
  static const Duration _violationDebounce = Duration(seconds: 2);
  DateTime? _lastViolationTime;

  // Suppresses violations while the violation dialog is open — prevents
  // the overlay from triggering extra increments on itself.
  bool _dialogOpen = false;

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
    if (!_isLockdownActive || _onViolation == null) return;

    // In debug mode, log but still fire the violation so developers can
    // test the flow. The kDebugMode guard was too aggressive — it silenced
    // violations entirely, making it impossible to verify the counter.
    if (kDebugMode) {
      debugPrint('[LockdownService] Violation (debug): $reason');
    }

    // Skip while the violation dialog is open — the overlay itself can
    // trigger a brief lifecycle pause on some devices/Android versions.
    if (_dialogOpen) return;

    // Debounce: ignore rapid-fire duplicates within the debounce window.
    final now = DateTime.now();
    if (_lastViolationTime != null &&
        now.difference(_lastViolationTime!) < _violationDebounce) {
      return;
    }
    _lastViolationTime = now;

    _onViolation!(reason);
  }

  /// Call this when the violation dialog opens so lifecycle events triggered
  /// by the overlay itself don't count as additional violations.
  void notifyDialogOpen() => _dialogOpen = true;

  /// Call this when the violation dialog closes so violations resume.
  void notifyDialogClosed() {
    _dialogOpen = false;
    // Reset debounce so the next real violation is detected immediately.
    _lastViolationTime = null;
  }

  /// Handle App Lifecycle state transitions.
  /// Triggers a violation when the user leaves the app in any form:
  /// - paused   : app moved to background (home button / task switch)
  /// - hidden   : app fully hidden, Android 14+ / iOS equivalient
  /// - detached : app process still alive but UI detached (swiped from recents)
  void handleLifecycleState(AppLifecycleState state) {
    if (!_isLockdownActive) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      triggerViolation('You left the app during the assessment!');
    }
  }
}
