import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/warehouse_web_bridge.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';
import '../utils/warehouse_agent_shop_identity_one_file.dart';

/// Mobile app user login provider
/// Нэгтгэсэн login логик: warehouse backend login + Weve site authentication
class MobileUserLoginProvider extends ChangeNotifier {
  final WarehouseWebBridge _bridge;

  bool _isLoading = false;
  String? _error;
  bool _isLoggedIn = false;
  User? _user;
  String? _token;
  bool _isRateLimited = false;
  DateTime? _rateLimitUntil;

  MobileUserLoginProvider({WarehouseWebBridge? bridge})
      : _bridge = bridge ?? WarehouseWebBridge() {
    _init();
  }

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isLoggedIn => _isLoggedIn;
  User? get user => _user;
  String? get token => _token;
  bool get isRateLimited => _isRateLimited;
  DateTime? get rateLimitUntil => _rateLimitUntil;

  Future<void> _init() async {
    // Respect "Remember me": if user didn't opt in, don't auto-load token.
    final prefs = await SharedPreferences.getInstance();
    final rememberMe = prefs.getBool('remember_me') ?? false;
    if (!rememberMe) return;

    final savedToken = await _bridge.loadToken();
    if (savedToken != null && savedToken.isNotEmpty) {
      _token = savedToken;
      _isLoggedIn = true;
      // Try to load user profile
      try {
        await _loadUserProfile();
      } catch (e) {
        debugPrint('Failed to load user profile: $e');
      }
      notifyListeners();
    }
  }

  /// Нэгтгэсэн login функц
  /// - @warehouse.com/@oasis.mn email-үүд: зөвхөн backend login
  /// - Бусад username-ууд: эхлээд Weve site agent-login, дараа нь backend login fallback
  Future<bool> login({
    required String identifier,
    required String password,
    AuthProvider? authProvider,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Token + embedded user from login response (works even when auth/profile fails).
      final outcome = await _bridge.loginWithDetails(
        identifier: identifier,
        password: password,
      );

      _token = outcome.token;

      final embedded = outcome.loginUser;
      if (embedded != null) {
        await _applyEmbeddedLoginUser(embedded,
            fallbackEmail: identifier.trim(), authProvider: authProvider);
      }

      // Login response-д user байхгүй үед л profile — давхар GET-ийг хэмнэнэ.
      if (_user == null || _user!.id.isEmpty) {
        await _loadUserProfile(authProvider: authProvider);
      }

      if (_user == null && authProvider?.user != null) {
        _user = authProvider!.user;
      }

      _isLoggedIn = true;
      _error = null; // Clear any previous errors
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      // Parse error and provide user-friendly messages
      final errorText = e.toString();

      // Check for DioException to get status code
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final responseData = e.response?.data;
        final errorMessage = responseData is Map
            ? responseData['message']?.toString() ?? ''
            : responseData?.toString() ?? '';

        if (statusCode == 429) {
          // Rate limiting error - block login attempts
          _isRateLimited = true;

          // Try to get Retry-After header
          final retryAfterHeader = e.response?.headers.value('retry-after');
          int? retryAfterSeconds;
          if (retryAfterHeader != null) {
            retryAfterSeconds = int.tryParse(retryAfterHeader);
          }

          // Default to 60 seconds if not specified
          final waitSeconds = retryAfterSeconds ?? 60;
          _rateLimitUntil = DateTime.now().add(Duration(seconds: waitSeconds));

          // Create user-friendly error message
          if (waitSeconds >= 60) {
            final minutes = (waitSeconds / 60).ceil();
            _error =
                'Хэт олон оролдлого хийсэн. Та $minutes минут хүлээгээд дахин оролдоно уу.';
          } else {
            _error =
                'Хэт олон оролдлого хийсэн. Та $waitSeconds секунд хүлээгээд дахин оролдоно уу.';
          }

          notifyListeners();

          // Auto-unblock after wait time
          Future.delayed(Duration(seconds: waitSeconds), () {
            _isRateLimited = false;
            _rateLimitUntil = null;
            notifyListeners();
          });
        } else {
          // Clear rate limit status for other errors
          _isRateLimited = false;
          _rateLimitUntil = null;

          final combined = '${e.message ?? ''} $errorText'.toLowerCase();
          if (combined.contains('certificate_verify_failed') ||
              combined.contains('ip address mismatch') ||
              combined.contains('handshakeexception')) {
            _error =
                'HTTPS сертификат энэ хаягтай таарахгүй (ихэвчлэн IP биш, домэйнээр хандана). '
                'Сүлжээний админтай холбогдоно уу. '
                'Дотоод тест: flutter run --dart-define=WAREHOUSE_TLS_INSECURE=true';
          } else if (e.type == DioExceptionType.connectionError &&
              (combined.contains('failed host lookup') ||
                  combined.contains('no address associated with hostname'))) {
            _error =
                'Серверийн домэйн DNS-д олдсонгүй (A/AAAA record байхгүй эсвэл буруу). '
                'Домэйн болон сүлжээгээ шалгана уу.';
          } else if (statusCode == 401 || statusCode == 403) {
            // Check if it's a user not registered error
            if (errorMessage.toLowerCase().contains('not registered') ||
                errorMessage.toLowerCase().contains('бүртгэлгүй') ||
                errorMessage.toLowerCase().contains('user not found') ||
                errorText.contains('USER_NOT_REGISTERED')) {
              _error =
                  'Та Weve сайтад бүртгэлгүй байна. Эхлээд Weve дээр бүртгүүлнэ үү.';
            } else {
              _error = 'Нэвтрэх нэр эсвэл нууц үг буруу байна.';
            }
          } else if (statusCode == 500 ||
              statusCode == 502 ||
              statusCode == 503) {
            _error = 'Серверийн алдаа гарлаа. Дахин оролдоно уу.';
          } else if (statusCode == 404) {
            final raw404 = errorMessage.toLowerCase();
            if (raw404.contains('nginx') ||
                raw404.contains('<html') ||
                raw404.contains('404 not found')) {
              _error =
                  'Nginx /api зам backend руу холбогдоогүй байна (HTML 404). '
                  'Серверийн proxy болон firewall тохиргоог шалгана уу.';
            } else {
              _error = 'Сервис олдсонгүй. Холболтоо шалгана уу.';
            }
          } else {
            _error = errorMessage.isNotEmpty
                ? errorMessage
                : 'Нэвтрэх үед алдаа гарлаа. Дахин оролдоно уу.';
          }
        }
      } else {
        // Non-DioException errors
        if (errorText.contains('USER_NOT_REGISTERED')) {
          _error =
              'Та Weve сайтад бүртгэлгүй байна. Эхлээд Weve дээр бүртгүүлнэ үү.';
        } else if (errorText.contains('CERTIFICATE_VERIFY_FAILED') ||
            errorText.contains('HandshakeException') ||
            errorText.contains('IP address mismatch')) {
          _error =
              'HTTPS сертификат энэ хаягтай таарахгүй. Домэйнээр хандах эсвэл түр: WAREHOUSE_TLS_INSECURE=true';
        } else if (errorText.contains('Failed host lookup') ||
            errorText.contains('No address associated with hostname')) {
          _error =
              'Домэйн DNS-д олдсонгүй. A/AAAA record болон сүлжээгээ шалгана уу.';
        } else if (errorText.contains('connection') ||
            errorText.contains('timeout') ||
            errorText.contains('network') ||
            errorText.contains('SocketException')) {
          _error = 'Холболтын алдаа. Интернэт холболтоо шалгана уу.';
        } else if (errorText.contains('401') ||
            errorText.contains('403') ||
            errorText.contains('Invalid credentials') ||
            errorText.contains('буруу байна')) {
          _error = 'Нэвтрэх нэр эсвэл нууц үг буруу байна.';
        } else {
          // Generic error message
          _error = 'Нэвтрэх үед алдаа гарлаа. Дахин оролдоно уу.';
        }
      }

      _isLoggedIn = false;
      _token = null;
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Apply remember-me preference after a successful login.
  /// If disabled, clears stored token so next app start won't auto-login.
  Future<void> applyRememberMe(bool rememberMe) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('remember_me', rememberMe);
    if (!rememberMe) {
      await _bridge.clearToken();
      _token = null;
      _isLoggedIn = false;
      notifyListeners();
    }
  }

  /// `auth/login` / `auth/agent-login` хариунд ирсэн user-ээр (profile байхгүй үед) ID тохируулна.
  Future<void> _applyEmbeddedLoginUser(
    Map<String, dynamic> m, {
    required String fallbackEmail,
    AuthProvider? authProvider,
  }) async {
    final idStr = (m['id'] ?? '').toString().trim();
    if (idStr.isEmpty) return;

    final rawEmail = m['email']?.toString().trim() ?? '';
    final email = rawEmail.isEmpty ? fallbackEmail : rawEmail;

    _user = User(
      id: idStr,
      name: m['displayName']?.toString() ?? m['name']?.toString() ?? 'User',
      email: email,
      role: (m['roleDisplay']?.toString() ?? m['role']?.toString() ?? 'user')
          .toLowerCase(),
      companyId:
          m['store'] is Map ? (m['store'] as Map)['id']?.toString() : null,
      createdAt: DateTime.now(),
    );

    final agentIdInt =
        WarehouseAgentShopIdentity.parseAgentIdFromEmbeddedLoginPersonMap(m);
    if (agentIdInt != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(WarehouseAgentShopIdentity.prefsAgentIdKey, agentIdInt);
    }

    if (authProvider != null) {
      await authProvider.updateFromBackend(
        id: _user!.id,
        name: _user!.name,
        email: _user!.email,
        role: _user!.role,
      );
    }
  }

  /// Load user profile from backend
  Future<void> _loadUserProfile({AuthProvider? authProvider}) async {
    try {
      final profileData = await _bridge.getProfile();
      if (kDebugMode) {
        debugPrint(
            '[Login] profile keys=${profileData.keys} userType=${profileData['user']?.runtimeType} employeeType=${profileData['employee']?.runtimeType}');
      }
      final rawUser = profileData['user'] ?? profileData['employee'];
      final Map<String, dynamic>? userData;
      if (rawUser is Map) {
        userData = rawUser.map((k, v) => MapEntry(k.toString(), v));
      } else if (profileData.isNotEmpty) {
        // Some backends return the user fields at the top level (no `user` wrapper).
        userData = profileData;
      } else {
        userData = null;
      }

      if (userData != null) {
        _user = User(
          id: (userData['id'] ?? '').toString(),
          name: userData['displayName']?.toString() ??
              userData['name']?.toString() ??
              'User',
          email: userData['email']?.toString() ?? '',
          role: userData['roleDisplay']?.toString().toLowerCase() ??
              userData['role']?.toString().toLowerCase() ??
              'user',
          companyId: userData['store']?['id']?.toString(),
          createdAt: DateTime.now(),
        );

        final agentIdInt =
            WarehouseAgentShopIdentity.parseAgentIdFromProfileOrUserMap(
                userData);
        if (agentIdInt != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(
              WarehouseAgentShopIdentity.prefsAgentIdKey, agentIdInt);
          debugPrint('✅ Agent ID хадгалагдлаа: $agentIdInt');
        }

        // Update AuthProvider if provided
        if (authProvider != null) {
          await authProvider.updateFromBackend(
            id: _user!.id,
            name: _user!.name,
            email: _user!.email,
            role: _user!.role,
          );
        }
      } else {
        debugPrint(
            'Failed to load user profile: missing user payload. profileData=$profileData');
      }
    } catch (e) {
      debugPrint('Failed to load user profile: $e');
      // Continue even if profile fetch fails
    }
  }

  /// Logout
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _bridge.clearToken();
      _token = null;
      _user = null;
      _isLoggedIn = false;
      _error = null;
    } catch (e) {
      debugPrint('Logout error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clear error
  void clearError() {
    _error = null;
    _isRateLimited = false;
    _rateLimitUntil = null;
    notifyListeners();
  }

  /// Check if login is currently blocked due to rate limiting
  bool get canAttemptLogin {
    if (!_isRateLimited) return true;
    if (_rateLimitUntil == null) return true;
    return DateTime.now().isAfter(_rateLimitUntil!);
  }
}
