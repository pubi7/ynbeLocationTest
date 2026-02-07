import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/warehouse_web_bridge.dart';
import '../models/user_model.dart';
import 'auth_provider.dart';

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
      // Use WarehouseWebBridge.login() which handles all login logic:
      // - @warehouse.com/@oasis.mn emails: normal login only
      // - Other usernames: try agent-login first, then fallback to normal login
      final token = await _bridge.login(
        identifier: identifier,
        password: password,
      );

      // Save token
      _token = token;

      // Load user profile and update AuthProvider
      await _loadUserProfile(authProvider: authProvider);

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

          if (statusCode == 401 || statusCode == 403) {
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
            _error = 'Сервис олдсонгүй. Холболтоо шалгана уу.';
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

  /// Load user profile from backend
  Future<void> _loadUserProfile({AuthProvider? authProvider}) async {
    try {
      final profileData = await _bridge.getProfile();
      final userData = profileData['user'] as Map<String, dynamic>?;

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

        // Extract and save agent ID if available
        final agentId = userData['agentId'] ?? userData['id'];
        if (agentId != null) {
          final agentIdInt = (agentId is num)
              ? agentId.toInt()
              : int.tryParse(agentId.toString());
          if (agentIdInt != null) {
            // Save to SharedPreferences for LocationProvider
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('agent_id', agentIdInt);
            debugPrint('✅ Agent ID хадгалагдлаа: $agentIdInt');
          }
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
