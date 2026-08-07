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
  // Prevents a single real event (e.g. `hidden` immediately followed by
  // `paused` for the same backgrounding) from being counted twice.
  // Kept at 1 s so rapid-but-distinct leave events (e.g. user opens another
  // app twice in quick succession) are still counted as two violations.
  static const Duration _violationDebounce = Duration(seconds: 1);
  DateTime? _lastViolationTime;

  // Grace period after enableLockdown()/re-enableLockdown() completes.
  // Toggling SystemChrome immersive mode and the native FLAG_SECURE bridge
  // can itself cause a brief onPause/onResume blip on some Android OEM
  // skins — most noticeably right after the dialog is dismissed and
  // lockdown is re-armed. Without this, that blip was being read as a
  // brand-new violation and could reopen the dialog immediately.
  static const Duration _reenableGracePeriod = Duration(milliseconds: 900);
  DateTime? _lockdownReadyAt;

  // Grace period after the violation dialog opens. On some devices,
  // presenting the overlay route itself causes one brief spurious pause.
  // This window is intentionally SHORT and does NOT suppress violations
  // for the dialog's entire lifetime — a genuine second violation (user
  // backgrounds the app again while the suspension countdown is running)
  // must still be counted, or the counter/dots never update and it looks
  // like violations "stop incrementing".
  static const Duration _dialogOpenGracePeriod = Duration(milliseconds: 900);
  bool _dialogOpen = false;
  DateTime? _dialogOpenedAt;

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

    // Stamped BEFORE the SystemChrome/native calls below — not after.
    // Those calls are exactly what can trigger the spurious OEM
    // pause/hidden blip, so the grace window must cover the whole
    // re-arm sequence (including the async gap while awaiting them),
    // not just start once they've already finished.
    _lockdownReadyAt = DateTime.now();

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
    _lockdownReadyAt = null;
    _dialogOpen = false;
    _dialogOpenedAt = null;

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

    final now = DateTime.now();

    // Ignore the brief blip that can follow (re)enabling lockdown — native
    // flag / SystemChrome toggles occasionally cause a spurious pause on
    // some devices. This is the main source of the "opened the dialog,
    // dismissed it, and it immediately reopened" and "counter stuck"
    // reports, since a stray event here used to slip past every other
    // guard and fire a fresh violation right after re-arming.
    if (_lockdownReadyAt != null &&
        now.difference(_lockdownReadyAt!) < _reenableGracePeriod) {
      if (kDebugMode) {
        debugPrint('[LockdownService] Ignored (post-enable blip): $reason');
      }
      return;
    }

    // Ignore only the FIRST brief instant right as the dialog opens — this
    // does NOT block violations for the dialog's whole lifetime. A real
    // second violation while the dialog is still up (user backgrounds the
    // app again during the suspension countdown) must still be counted,
    // otherwise the counter/dots never advance past 1.
    if (_dialogOpen &&
        _dialogOpenedAt != null &&
        now.difference(_dialogOpenedAt!) < _dialogOpenGracePeriod) {
      if (kDebugMode) {
        debugPrint('[LockdownService] Ignored (dialog-open blip): $reason');
      }
      return;
    }

    // Debounce: ignore rapid-fire duplicates within the debounce window
    // (e.g. `hidden` and `paused` firing back-to-back for one real event).
    if (_lastViolationTime != null &&
        now.difference(_lastViolationTime!) < _violationDebounce) {
      return;
    }
    _lastViolationTime = now;

    _onViolation!(reason);
  }

  /// Call this when the violation dialog opens. Only used to absorb the
  /// brief open-transition blip — it no longer suppresses violations for
  /// as long as the dialog stays visible.
  void notifyDialogOpen() {
    _dialogOpen = true;
    _dialogOpenedAt = DateTime.now();
  }

  /// Call this when the violation dialog closes so violations resume.
  void notifyDialogClosed() {
    _dialogOpen = false;
    _dialogOpenedAt = null;
    // Reset debounce so the next real violation is detected immediately.
    _lastViolationTime = null;
  }

  /// Handle App Lifecycle state transitions.
  /// Triggers a violation ONLY when the user actually leaves the app and it goes to the background:
  /// - paused   : app moved to background (home button / task switch)
  /// - hidden   : app fully hidden (Android 14+ / iOS equivalent)
  /// - detached : app process still alive but UI detached
  void handleLifecycleState(AppLifecycleState state) {
    if (!_isLockdownActive) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      triggerViolation('You left the app during the assessment!');
    } else if (state == AppLifecycleState.resumed) {
      // Reset the debounce timer on resume so that if the user leaves again
      // right after returning, the new leave is not silently swallowed.
      _lastViolationTime = null;
    }
  }
}
