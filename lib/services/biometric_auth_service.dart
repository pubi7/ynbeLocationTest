import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;

class BiometricAuthService {
  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> isSupported() async {
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;
      return await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> authenticate({String reason = 'Нэвтрэх'}) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[BiometricAuth] authenticate error: $e');
      }
      // Treat some “not available” cases as false rather than crashing.
      if (e.toString().contains(auth_error.notAvailable) ||
          e.toString().contains(auth_error.notEnrolled) ||
          e.toString().contains(auth_error.lockedOut) ||
          e.toString().contains(auth_error.permanentlyLockedOut)) {
        return false;
      }
      return false;
    }
  }
}
