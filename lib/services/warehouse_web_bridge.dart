import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/product_model.dart';
import '../models/shop_model.dart';

// -------- Isolate-safe extraction (compute requires sendable types) --------

List<Map<String, dynamic>> _extractProductMaps(List<dynamic> raw) {
  final out = <Map<String, dynamic>>[];
  for (final p0 in raw) {
    if (p0 is! Map) continue;
    final p = p0.cast<String, dynamic>();
    out.add({
      'id': p['id']?.toString(),
      'nameMongolian': p['nameMongolian']?.toString(),
      'nameEnglish': p['nameEnglish']?.toString(),
      'productCode': p['productCode']?.toString(),
      'barcode': p['barcode']?.toString(),
      'stockQuantity': (p['stockQuantity'] is num)
          ? (p['stockQuantity'] as num).toInt()
          : null,
      'unitsPerBox':
          (p['unitsPerBox'] is num) ? (p['unitsPerBox'] as num).toInt() : null,
      // Keep prices as numbers if possible, convert to string only if needed
      'priceWholesale': (p['priceWholesale'] is num)
          ? (p['priceWholesale'] as num).toDouble()
          : (p['priceWholesale']?.toString()),
      'priceRetail': (p['priceRetail'] is num)
          ? (p['priceRetail'] as num).toDouble()
          : (p['priceRetail']?.toString()),
      'pricePerBox': (p['pricePerBox'] is num)
          ? (p['pricePerBox'] as num).toDouble()
          : (p['pricePerBox']?.toString()),
      // Optional Weve/Backend campaign fields (if backend provides)
      'discountPercent': (p['discountPercent'] ??
              p['discount'] ??
              p['campaignDiscountPercent'])
          ?.toString(),
      'promotionText':
          (p['promotionText'] ?? p['promotion'] ?? p['campaignTitle'])
              ?.toString(),
      'netWeight': p['netWeight']?.toString(),
      'grossWeight': p['grossWeight']?.toString(),
      'categoryName': (p['category'] is Map)
          ? (p['category'] as Map)['nameMongolian']?.toString()
          : null,
      'supplierName': (p['supplier'] is Map)
          ? (p['supplier'] as Map)['name']?.toString()
          : null,
      // Product active status (default to true if not provided)
      'isActive': p['isActive'] ?? p['active'] ?? true,
    });
  }
  return out;
}

List<Map<String, dynamic>> _extractShopMaps(List<dynamic> raw) {
  final out = <Map<String, dynamic>>[];
  for (final c0 in raw) {
    if (c0 is! Map) continue;
    final c = c0.cast<String, dynamic>();
    out.add({
      'id': c['id']?.toString(),
      'name': c['name']?.toString(),
      'district': c['district']?.toString(),
      'address': c['address']?.toString(),
      'detailedAddress': c['detailedAddress']?.toString(),
      'phoneNumber': c['phoneNumber']?.toString(),
      'registrationNumber': c['registrationNumber']?.toString(),
      // Optional: purchase limit fields (backend dependent)
      'maxPurchaseAmount': (c['maxPurchaseAmount'] ??
              c['purchaseLimit'] ??
              c['maxOrderAmount'] ??
              c['creditLimit'])
          ?.toString(),
      'locationLatitude': (c['locationLatitude'] is num)
          ? (c['locationLatitude'] as num).toDouble()
          : null,
      'locationLongitude': (c['locationLongitude'] is num)
          ? (c['locationLongitude'] as num).toDouble()
          : null,
    });
  }
  return out;
}

class _RetryInterceptor extends Interceptor {
  final Dio dio;
  final int retries;
  final List<Duration> retryDelays;

  _RetryInterceptor({
    required this.dio,
    this.retries = 2,
    this.retryDelays = const [Duration(seconds: 1), Duration(seconds: 2)],
  });

  bool _shouldRetry(DioException e) {
    final code = e.response?.statusCode;
    // Never retry 429 (Too Many Requests) - wait and let user retry manually
    if (code == 429) return false;
    if (code != null && (code == 502 || code == 503 || code == 504))
      return true;
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError;
  }

  @override
  Future<void> onError(
      DioException err, ErrorInterceptorHandler handler) async {
    final extra = err.requestOptions.extra;
    final attempt = (extra['retry_attempt'] as int?) ?? 0;
    if (attempt >= retries || !_shouldRetry(err)) {
      return handler.next(err);
    }

    final delay =
        retryDelays.length > attempt ? retryDelays[attempt] : retryDelays.last;
    await Future<void>.delayed(delay);

    final options = err.requestOptions;
    options.extra['retry_attempt'] = attempt + 1;

    try {
      final response = await dio.fetch(options);
      return handler.resolve(response);
    } catch (e) {
      return handler.next(e is DioException ? e : err);
    }
  }
}

/// Single source of truth for **Web site -> Mobile app** sync.
///
/// Backend expected baseUrl: `${BACKEND_SERVER_URL}/api`
///
/// Endpoints used:
/// - POST `auth/login`  -> { status: "success", data: { token: "..." } }
/// - POST `auth/agent-login` -> { status: "success", data: { token: "...", agent: {...} } }
/// - GET  `products`    -> { status: "success", data: { products: [], pagination: { totalPages } } }
/// - GET  `customers`   -> { status: "success", data: { customers: [], pagination: { totalPages } } }
class WarehouseWebBridge {
  static const _prefsTokenKey = 'warehouse_token';
  static const _prefsApiBaseUrlKey = 'warehouse_api_base_url';

  final Dio _dio;

  /// Called when backend returns 401 and token is cleared.
  VoidCallback? onUnauthorized;

  WarehouseWebBridge({Dio? dio, this.onUnauthorized})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConfig.warehouseApiBaseUrl,
                connectTimeout:
                    const Duration(seconds: 30), // Increased for slow networks
                sendTimeout:
                    const Duration(seconds: 30), // Increased for slow networks
                receiveTimeout: const Duration(
                    seconds: 60), // Increased for large responses
                headers: const {'Content-Type': 'application/json'},
              ),
            ) {
    _dio.interceptors.add(
      _RetryInterceptor(
        dio: _dio,
        retries: 2,
        retryDelays: const [Duration(seconds: 1), Duration(seconds: 2)],
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (kDebugMode)
            debugPrint('[WebBridge] → ${options.method} ${options.uri}');
          handler.next(options);
        },
        onResponse: (resp, handler) {
          if (kDebugMode)
            debugPrint(
                '[WebBridge] ← ${resp.statusCode} ${resp.requestOptions.uri}');
          handler.next(resp);
        },
        onError: (e, handler) async {
          if (e.response?.statusCode == 401) {
            await clearToken();
            onUnauthorized?.call();
          }
          if (kDebugMode) {
            debugPrint('[WebBridge] ✗ ${e.type} ${e.requestOptions.uri}');
            if (e.response != null) {
              debugPrint(
                  '[WebBridge] ✗ status=${e.response?.statusCode} body=${e.response?.data}');
            } else {
              debugPrint('[WebBridge] ✗ message=${e.message}');
            }
          }
          handler.next(e);
        },
      ),
    );
  }

  Dio get dio => _dio;

  void setToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  String get apiBaseUrl => _dio.options.baseUrl;

  String _normalizeApiBaseUrl(String input) {
    var s = input.trim();
    if (s.isEmpty) return ApiConfig.warehouseApiBaseUrl;

    // Allow user to enter either:
    // - http://host:port
    // - http://host:port/api
    // Normalize to .../api/ (with trailing slash).
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    if (!s.toLowerCase().endsWith('/api')) {
      s = '$s/api';
    }
    if (!s.endsWith('/')) s = '$s/';
    return s;
  }

  Future<String?> loadApiBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_prefsApiBaseUrlKey);
    if (v == null || v.trim().isEmpty) return null;
    return _normalizeApiBaseUrl(v);
  }

  Future<void> saveApiBaseUrl(String apiBaseUrl) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsApiBaseUrlKey, apiBaseUrl.trim());
  }

  Future<void> setApiBaseUrl(String apiBaseUrl) async {
    final normalized = _normalizeApiBaseUrl(apiBaseUrl);
    _dio.options.baseUrl = normalized;
    // Ensure timeouts are set when changing base URL
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.sendTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 60);
  }

  Future<void> saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsTokenKey, token);
  }

  Future<String?> loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_prefsTokenKey);
    if (token != null && token.isNotEmpty) {
      setToken(token);
      return token;
    }
    return null;
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsTokenKey);
    _dio.options.headers.remove('Authorization');
  }

  Map<String, dynamic> _unwrapData(Map<String, dynamic> body) {
    if (kDebugMode) {
      debugPrint('[WebBridge] Unwrapping response: keys=${body.keys}');
    }

    final status = body['status']?.toString();
    if (status != null && status != 'success') {
      final message = body['message'] ?? 'Request failed';
      if (kDebugMode) {
        debugPrint(
            '[WebBridge] ❌ Response status is not success: $status - $message');
      }
      throw Exception(message);
    }
    final data = body['data'];
    if (data is Map) {
      if (kDebugMode) {
        debugPrint('[WebBridge] ✅ Unwrapped data with keys: ${data.keys}');
      }
      return data.cast<String, dynamic>();
    }
    if (kDebugMode) {
      debugPrint('[WebBridge] ⚠️ No data field found, returning body as-is');
    }
    return body;
  }

  Future<Map<String, dynamic>> _getJson(String path,
      {Map<String, dynamic>? qp}) async {
    try {
      final r = await _dio.get<Map<String, dynamic>>(path, queryParameters: qp);
      if (kDebugMode) {
        debugPrint('[WebBridge] Response status: ${r.statusCode}');
      }
      return r.data ?? <String, dynamic>{};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebBridge] Error in _getJson for $path: $e');
        if (e is DioException) {
          debugPrint('[WebBridge] Status: ${e.response?.statusCode}');
          debugPrint('[WebBridge] Response data: ${e.response?.data}');
        }
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _postJson(String path, {Object? data}) async {
    try {
      if (kDebugMode) {
        debugPrint('[WebBridge] POST $path');
        debugPrint('[WebBridge] Base URL: ${_dio.options.baseUrl}');
        debugPrint('[WebBridge] Full URL: ${_dio.options.baseUrl}$path');
        debugPrint(
            '[WebBridge] Connect timeout: ${_dio.options.connectTimeout}');
      }
      final r = await _dio.post<Map<String, dynamic>>(path, data: data);
      if (kDebugMode) {
        debugPrint('[WebBridge] POST Response status: ${r.statusCode}');
        debugPrint('[WebBridge] POST Response data: ${r.data}');
      }
      return r.data ?? <String, dynamic>{};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebBridge] ❌ Error in _postJson for $path: $e');
        if (e is DioException) {
          debugPrint('[WebBridge] Error type: ${e.type}');
          debugPrint('[WebBridge] Status: ${e.response?.statusCode}');
          debugPrint('[WebBridge] Response data: ${e.response?.data}');
          debugPrint('[WebBridge] Request URL: ${e.requestOptions.uri}');

          // Provide specific error messages for connection issues
          if (e.type == DioExceptionType.connectionTimeout) {
            debugPrint(
                '[WebBridge] ⚠️ Connection timeout - server may be unreachable or slow');
            debugPrint(
                '[WebBridge] ⚠️ Check if server at ${e.requestOptions.uri} is running');
          } else if (e.type == DioExceptionType.sendTimeout) {
            debugPrint(
                '[WebBridge] ⚠️ Send timeout - request took too long to send');
          } else if (e.type == DioExceptionType.receiveTimeout) {
            debugPrint(
                '[WebBridge] ⚠️ Receive timeout - response took too long');
          } else if (e.type == DioExceptionType.connectionError) {
            debugPrint('[WebBridge] ⚠️ Connection error - cannot reach server');
            debugPrint(
                '[WebBridge] ⚠️ Check network connection and server address');
          }
        }
      }
      rethrow;
    }
  }

  Future<String> login(
      {required String identifier, required String password}) async {
    // Strategy:
    // - If identifier ends with @warehouse.com, must exist in backend (normal login only)
    // - Otherwise, try agent-login first (Weve site authentication), then fallback to normal login

    if (kDebugMode) {
      debugPrint('[WebBridge] 🔐 Starting login for identifier: $identifier');
    }

    final isWarehouseEmail =
        identifier.toLowerCase().endsWith('@warehouse.com') ||
            identifier.toLowerCase().endsWith('@oasis.mn');

    if (isWarehouseEmail) {
      // @warehouse.com or @oasis.mn emails must exist in backend
      // Try normal warehouse login only (no agent-login fallback)
      if (kDebugMode) {
        debugPrint('[WebBridge] Using warehouse email login for: $identifier');
      }
      try {
        final body = await _postJson(
          'auth/login',
          data: {'identifier': identifier, 'password': password},
        );

        if (kDebugMode) {
          debugPrint('[WebBridge] Login response received: ${body.keys}');
        }

        final data = _unwrapData(body);
        final token = data['token']?.toString();

        if (token == null || token.isEmpty) {
          final errorMsg =
              body['message']?.toString() ?? 'Token not returned from server';
          if (kDebugMode) {
            debugPrint('[WebBridge] ❌ Login failed: $errorMsg');
          }
          throw Exception(errorMsg);
        }

        setToken(token);
        await saveToken(token);

        if (kDebugMode) {
          debugPrint('[WebBridge] ✅ Login successful for warehouse email');
        }

        return token;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[WebBridge] ❌ Warehouse login error: $e');
          if (e is DioException) {
            debugPrint('[WebBridge] Status: ${e.response?.statusCode}');
            debugPrint('[WebBridge] Response: ${e.response?.data}');
            debugPrint('[WebBridge] Error type: ${e.type}');

            // Provide specific guidance for connection issues
            if (e.type == DioExceptionType.connectionTimeout ||
                e.type == DioExceptionType.connectionError) {
              debugPrint('[WebBridge] ⚠️ CONNECTION ERROR DETECTED');
              debugPrint('[WebBridge] Server URL: ${_dio.options.baseUrl}');
              debugPrint('[WebBridge] Full URL: ${e.requestOptions.uri}');
              debugPrint('[WebBridge]');
              debugPrint('[WebBridge] Possible issues:');
              debugPrint('[WebBridge] 1. Server is not running');
              debugPrint('[WebBridge] 2. Server URL is incorrect');
              debugPrint('[WebBridge] 3. Network connectivity problem');
              if (kIsWeb) {
                debugPrint('[WebBridge] 4. CORS not enabled on server');
                debugPrint('[WebBridge]    → Server needs CORS headers:');
                debugPrint('[WebBridge]      Access-Control-Allow-Origin: *');
                debugPrint(
                    '[WebBridge]      Access-Control-Allow-Methods: GET, POST, OPTIONS');
                debugPrint(
                    '[WebBridge]      Access-Control-Allow-Headers: Content-Type, Authorization');
              }
              debugPrint('[WebBridge]');
              debugPrint(
                  '[WebBridge] To test connection, use: testConnection()');
            }
          }
        }
        // Re-throw DioException directly so MobileUserLoginProvider can handle it properly
        rethrow;
      }
    }

    // For non-warehouse emails, try agent-login first (Weve site authentication)
    if (kDebugMode) {
      debugPrint('[WebBridge] Trying agent-login first for: $identifier');
    }

    try {
      // First, try agent-login (Weve site authentication)
      final agentBody = await _postJson(
        'auth/agent-login',
        data: {'username': identifier, 'password': password},
      );

      if (kDebugMode) {
        debugPrint(
            '[WebBridge] Agent-login response received: ${agentBody.keys}');
      }

      // If agent-login succeeds, user is registered in Weve site
      final agentData = _unwrapData(agentBody);
      final agentToken = agentData['token']?.toString();

      if (agentToken != null && agentToken.isNotEmpty) {
        setToken(agentToken);
        await saveToken(agentToken);

        // Extract and save agent ID if available
        final agentInfo = agentData['agent'] as Map<String, dynamic>?;
        if (agentInfo != null) {
          final agentId = agentInfo['id'];
          if (agentId != null) {
            // Save agent ID to SharedPreferences for LocationProvider
            final prefs = await SharedPreferences.getInstance();
            final agentIdInt = (agentId is num)
                ? agentId.toInt()
                : int.tryParse(agentId.toString());
            if (agentIdInt != null) {
              await prefs.setInt('agent_id', agentIdInt);
              if (kDebugMode) {
                debugPrint('[WebBridge] ✅ Agent ID хадгалагдлаа: $agentIdInt');
              }
            }
          }
        }

        if (kDebugMode) {
          debugPrint('[WebBridge] ✅ Agent-login successful');
        }

        return agentToken;
      } else {
        if (kDebugMode) {
          debugPrint(
              '[WebBridge] ⚠️ Agent-login succeeded but no token received');
        }
        throw Exception('Token not returned from agent-login');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebBridge] Agent-login error: $e');
      }

      // If agent-login fails with 401/403, user is not registered in Weve site
      if (e is DioException) {
        final statusCode = e.response?.statusCode;
        final responseData = e.response?.data;
        final errorMessage = responseData is Map
            ? responseData['message']?.toString() ?? ''
            : responseData?.toString() ?? '';

        if (kDebugMode) {
          debugPrint('[WebBridge] Agent-login status: $statusCode');
          debugPrint('[WebBridge] Agent-login error message: $errorMessage');
        }

        if (statusCode == 404) {
          // Agent-login endpoint not available (old backend version) - fallback to normal login
          if (kDebugMode) {
            debugPrint(
                '[WebBridge] Agent login endpoint not available (404), trying normal login');
          }
        } else if (statusCode == 401 || statusCode == 403) {
          // User is not registered in Weve site - throw specific error
          if (errorMessage.toLowerCase().contains('not registered') ||
              errorMessage.toLowerCase().contains('бүртгэлгүй') ||
              errorMessage.toLowerCase().contains('user not found')) {
            if (kDebugMode) {
              debugPrint('[WebBridge] ❌ User not registered in Weve site');
            }
            throw Exception('USER_NOT_REGISTERED');
          } else {
            // For agent-login, 401/403 usually means not registered
            if (kDebugMode) {
              debugPrint('[WebBridge] ❌ User not registered (401/403)');
            }
            throw Exception('USER_NOT_REGISTERED');
          }
        } else {
          // For 429 and other errors - rethrow DioException so MobileUserLoginProvider can handle it
          if (kDebugMode) {
            debugPrint(
                '[WebBridge] Rethrowing DioException for status: $statusCode');
          }
          rethrow;
        }
      } else {
        // Non-DioException - check if it's already USER_NOT_REGISTERED
        if (e.toString().contains('USER_NOT_REGISTERED')) {
          rethrow;
        }
        // Other exceptions - rethrow
        rethrow;
      }
    }

    // Fallback to normal warehouse login (only if agent-login endpoint was 404)
    if (kDebugMode) {
      debugPrint('[WebBridge] Falling back to normal warehouse login');
    }

    try {
      final body = await _postJson(
        'auth/login',
        data: {'identifier': identifier, 'password': password},
      );

      if (kDebugMode) {
        debugPrint('[WebBridge] Normal login response received: ${body.keys}');
      }

      final data = _unwrapData(body);
      final token = data['token']?.toString();

      if (token == null || token.isEmpty) {
        final errorMsg =
            body['message']?.toString() ?? 'Token not returned from server';
        if (kDebugMode) {
          debugPrint('[WebBridge] ❌ Normal login failed: $errorMsg');
        }
        throw Exception(errorMsg);
      }

      setToken(token);
      await saveToken(token);

      if (kDebugMode) {
        debugPrint('[WebBridge] ✅ Normal login successful');
      }

      return token;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebBridge] ❌ Normal login error: $e');
        if (e is DioException) {
          debugPrint('[WebBridge] Status: ${e.response?.statusCode}');
          debugPrint('[WebBridge] Response: ${e.response?.data}');
        }
      }
      // If normal login also fails, rethrow DioException so MobileUserLoginProvider can handle it
      rethrow;
    }
  }

  /// Test connection to the server
  /// Returns true if server is reachable, false otherwise
  Future<bool> testConnection({Duration? timeout}) async {
    try {
      if (kDebugMode) {
        debugPrint(
            '[WebBridge] 🔍 Testing connection to ${_dio.options.baseUrl}');
      }

      // Use a shorter timeout for connection test (default 5 seconds)
      final testTimeout = timeout ?? const Duration(seconds: 5);
      final testDio = Dio(BaseOptions(
        baseUrl: _dio.options.baseUrl,
        connectTimeout: testTimeout,
        receiveTimeout: testTimeout,
      ));

      // Try to reach a simple endpoint (health check or profile)
      // If no health endpoint exists, try profile endpoint
      try {
        await testDio.get(
          'auth/profile',
          options: Options(
            validateStatus: (status) =>
                status != null &&
                status < 500, // Accept 401/403 as "server is reachable"
          ),
        );
        if (kDebugMode) {
          debugPrint('[WebBridge] ✅ Connection test successful');
        }
        return true;
      } catch (e) {
        // If we get 401/403, server is reachable but we're not authenticated
        if (e is DioException && e.response != null) {
          final status = e.response?.statusCode;
          if (status == 401 || status == 403) {
            if (kDebugMode) {
              debugPrint(
                  '[WebBridge] ✅ Server is reachable (got $status - authentication required)');
            }
            return true;
          }
        }
        // Try a simple GET request to root or health endpoint
        try {
          await testDio.get(
            '',
            options: Options(
              validateStatus: (status) => true, // Accept any status
            ),
          );
          if (kDebugMode) {
            debugPrint(
                '[WebBridge] ✅ Connection test successful (root endpoint)');
          }
          return true;
        } catch (_) {
          rethrow;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebBridge] ❌ Connection test failed: $e');
        if (e is DioException) {
          debugPrint('[WebBridge] Error type: ${e.type}');
          debugPrint('[WebBridge] URL: ${e.requestOptions.uri}');
          if (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.connectionError) {
            debugPrint(
                '[WebBridge] ⚠️ Cannot reach server at ${_dio.options.baseUrl}');
            debugPrint('[WebBridge] ⚠️ Please check:');
            debugPrint('[WebBridge]   1. Server is running');
            debugPrint('[WebBridge]   2. Server URL is correct');
            debugPrint('[WebBridge]   3. Network connection');
            if (kIsWeb) {
              debugPrint('[WebBridge]   4. CORS is enabled on server');
            }
          }
        }
      }
      return false;
    }
  }

  /// Get current user profile
  Future<Map<String, dynamic>> getProfile() async {
    final body = await _getJson('auth/profile');
    return _unwrapData(body);
  }

  /// Fetch stores from Weve site for agent (uses agent's Weve token)
  Future<List<Shop>> fetchAgentStores() async {
    final shops = <Shop>[];

    try {
      final body = await _getJson('weve/agent/stores');
      final data = _unwrapData(body);
      final stores = (data['stores'] as List?) ?? const [];

      final extracted = await compute(_extractShopMaps, stores);
      for (final s in extracted) {
        final name = (s['name'] ?? 'N/A').toString();
        final district = (s['district'] ?? '').toString().trim();
        final address = (s['address'] ?? '').toString().trim();
        final detailedAddress = (s['detailedAddress'] ?? '').toString().trim();
        final fullAddress = [district, address, detailedAddress]
            .where((s) => s.trim().isNotEmpty)
            .join(', ');
        final maxPurchaseAmount =
            double.tryParse((s['maxPurchaseAmount'] ?? '').toString());

        shops.add(
          Shop(
            id: (s['id'] ?? '').toString(),
            name: name,
            address: fullAddress.isEmpty ? 'N/A' : fullAddress,
            latitude: (s['locationLatitude'] as double?) ?? 0.0,
            longitude: (s['locationLongitude'] as double?) ?? 0.0,
            phone: (s['phoneNumber'] ?? '').toString(),
            email: null,
            registrationNumber: s['registrationNumber']?.toString(),
            maxPurchaseAmount: maxPurchaseAmount,
            status: 'active',
            orders: const [],
            sales: const [],
            lastVisit: DateTime.now(),
          ),
        );
      }
    } catch (e) {
      // If agent stores fetch fails, fallback to regular customers endpoint
      debugPrint('Failed to fetch agent stores from Weve: $e');
      return await fetchAllShops();
    }

    return shops;
  }

  /// Helper method to parse price from various formats
  double? _parsePrice(dynamic value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value == null) return null;
    final str = value.toString().trim();
    if (str.isEmpty) return null;
    return double.tryParse(str);
  }

  /// Helper method to extract primary price (retail > wholesale > perBox)
  double _extractPrimaryPrice(Map<String, dynamic> p) {
    final retail = _parsePrice(p['priceRetail']);
    if (retail != null && retail > 0) return retail;

    final wholesale = _parsePrice(p['priceWholesale']);
    if (wholesale != null && wholesale > 0) return wholesale;

    final perBox = _parsePrice(p['pricePerBox']);
    if (perBox != null && perBox > 0) return perBox;

    return 0.0;
  }

  /// Helper method to convert extracted product map to Product model
  Product _mapToProduct(Map<String, dynamic> p) {
    final id = (p['id'] ?? '').toString();
    final name = (p['nameMongolian'] ?? p['nameEnglish'] ?? 'N/A').toString();
    final price = _extractPrimaryPrice(p);

    if (kDebugMode && price == 0.0) {
      debugPrint(
          '[WebBridge] ⚠️ Product $id ($name) has no price. Retail: ${p['priceRetail']}, Wholesale: ${p['priceWholesale']}, PerBox: ${p['pricePerBox']}');
    }

    final discountPercent =
        int.tryParse((p['discountPercent'] ?? '').toString());
    final promotionText = (p['promotionText'] ?? '').toString().trim();

    return Product(
      id: id,
      name: name,
      price: price,
      discountPercent: discountPercent,
      promotionText: promotionText.isEmpty ? null : promotionText,
      description: p['nameEnglish']?.toString(),
      category: p['categoryName']?.toString(),
      supplierName: p['supplierName']?.toString(),
      barcode: p['barcode']?.toString(),
      productCode: p['productCode']?.toString(),
      stockQuantity: p['stockQuantity'] as int?,
      unitsPerBox: p['unitsPerBox'] as int?,
      netWeight: _parsePrice(p['netWeight']),
      grossWeight: _parsePrice(p['grossWeight']),
      priceWholesale: _parsePrice(p['priceWholesale']),
      priceRetail: _parsePrice(p['priceRetail']),
      pricePerBox: _parsePrice(p['pricePerBox']),
    );
  }

  /// Helper method to check if error is retryable
  bool _isRetryableError(dynamic error) {
    if (error is! DioException) return false;
    return error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.response?.statusCode == 502 ||
        error.response?.statusCode == 503 ||
        error.response?.statusCode == 504;
  }

  /// Fetch all products from warehouse backend with pagination support
  ///
  /// Fetches products page by page until all pages are retrieved.
  /// Supports retry logic for transient network errors.
  Future<List<Product>> fetchAllProducts({
    int pageSize = 200,
    bool includeInactive = true,
  }) async {
    final products = <Product>[];
    var page = 1;
    var totalPages = 1;
    int retryCount = 0;
    const maxRetries = 3;

    if (kDebugMode) {
      debugPrint(
          '[WebBridge] 🚀 Starting product fetch (pageSize: $pageSize, includeInactive: $includeInactive)');
    }

    try {
      do {
        if (kDebugMode) {
          debugPrint(
              '[WebBridge] 📄 Fetching products page $page/$totalPages...');
        }

        try {
          // Build query parameters
          final queryParams = <String, dynamic>{
            'limit': pageSize,
            'page': page,
          };
          if (includeInactive) {
            queryParams['includeInactive'] = 'true';
          }

          // Fetch products page
          final body = await _getJson('products', qp: queryParams);
          final data = _unwrapData(body);
          final rawProducts = (data['products'] as List?) ?? const [];

          if (kDebugMode) {
            debugPrint(
                '[WebBridge] 📦 Found ${rawProducts.length} products in page $page');
          }

          // Extract pagination info
          final pagination = (data['pagination'] is Map)
              ? (data['pagination'] as Map).cast<String, dynamic>()
              : <String, dynamic>{};
          totalPages = (pagination['totalPages'] as num?)?.toInt() ?? 1;

          if (rawProducts.isEmpty && page < totalPages && kDebugMode) {
            debugPrint(
                '[WebBridge] ⚠️ Empty page $page but totalPages is $totalPages');
          }

          // Extract and convert products
          final extracted = await compute(_extractProductMaps, rawProducts);
          if (kDebugMode) {
            debugPrint(
                '[WebBridge] Extracted ${extracted.length} products from page $page');
          }

          for (final p in extracted) {
            final product = _mapToProduct(p);
            products.add(product);
            if (kDebugMode && product.price > 0) {
              debugPrint(
                  '[WebBridge] ✅ Product ${product.id} (${product.name}) - Price: ${product.price}');
            }
          }

          page += 1;
          retryCount = 0; // Reset retry count on success
        } catch (e) {
          retryCount++;
          if (kDebugMode) {
            debugPrint(
                '[WebBridge] ⚠️ Error fetching page $page (attempt $retryCount/$maxRetries): $e');
          }

          // Retry logic for transient errors
          if (retryCount < maxRetries && _isRetryableError(e)) {
            final delayMs = retryCount * 1000; // Exponential backoff
            if (kDebugMode) {
              debugPrint(
                  '[WebBridge] 🔄 Retrying page $page after ${delayMs}ms...');
            }
            await Future.delayed(Duration(milliseconds: delayMs));
            continue; // Retry same page
          } else {
            // Max retries reached or non-retryable error
            if (kDebugMode) {
              debugPrint(
                  '[WebBridge] ❌ Failed to fetch page $page after $retryCount attempts');
            }
            // Return partial results if available
            if (products.isNotEmpty) {
              if (kDebugMode) {
                debugPrint(
                    '[WebBridge] ⚠️ Returning ${products.length} products fetched so far (page $page failed)');
              }
              return products;
            }
            // No products yet, rethrow error
            rethrow;
          }
        }
      } while (page <= totalPages);

      if (kDebugMode) {
        debugPrint(
            '[WebBridge] ✅ Successfully fetched ${products.length} total products from $totalPages pages');
        if (products.isNotEmpty) {
          final productsWithPrice = products.where((p) => p.price > 0).length;
          debugPrint(
              '[WebBridge] 📊 Product summary: ${products.length} total, $productsWithPrice with prices');
        }
      }

      return products;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[WebBridge] ❌ Fatal error fetching products: $e');
        if (e is DioException) {
          debugPrint('[WebBridge] Status: ${e.response?.statusCode}');
          debugPrint('[WebBridge] Response: ${e.response?.data}');
        }
        debugPrint('[WebBridge] Stack trace: $stackTrace');
      }
      rethrow;
    }
  }

  Future<List<Shop>> fetchAllShops({int pageSize = 200}) async {
    final shops = <Shop>[];
    var page = 1;
    var totalPages = 1;

    try {
      do {
        if (kDebugMode) {
          debugPrint('[WebBridge] Fetching shops page $page...');
        }
        final body =
            await _getJson('customers', qp: {'limit': pageSize, 'page': page});

        if (kDebugMode) {
          debugPrint('[WebBridge] Received customers response: ${body.keys}');
        }

        final data = _unwrapData(body);
        final customers = (data['customers'] as List?) ?? const [];

        if (kDebugMode) {
          debugPrint(
              '[WebBridge] Found ${customers.length} customers in page $page');
        }

        final pagination = (data['pagination'] is Map)
            ? (data['pagination'] as Map).cast<String, dynamic>()
            : <String, dynamic>{};
        totalPages = (pagination['totalPages'] as num?)?.toInt() ?? 1;

        final extracted = await compute(_extractShopMaps, customers);
        if (kDebugMode) {
          debugPrint(
              '[WebBridge] Extracted ${extracted.length} shops from page $page');
        }
        for (final c in extracted) {
          final name = (c['name'] ?? 'N/A').toString();
          final district = (c['district'] ?? '').toString().trim();
          final address = (c['address'] ?? '').toString().trim();
          final detailedAddress =
              (c['detailedAddress'] ?? '').toString().trim();
          final fullAddress = [district, address, detailedAddress]
              .where((s) => s.trim().isNotEmpty)
              .join(', ');
          final maxPurchaseAmount =
              double.tryParse((c['maxPurchaseAmount'] ?? '').toString());

          shops.add(
            Shop(
              id: (c['id'] ?? '').toString(),
              name: name,
              address: fullAddress.isEmpty ? 'N/A' : fullAddress,
              latitude: (c['locationLatitude'] as double?) ?? 0.0,
              longitude: (c['locationLongitude'] as double?) ?? 0.0,
              phone: (c['phoneNumber'] ?? '').toString(),
              email: null,
              registrationNumber: c['registrationNumber']?.toString(),
              maxPurchaseAmount: maxPurchaseAmount,
              status: 'active',
              orders: const [],
              sales: const [],
              lastVisit: DateTime.now(),
            ),
          );
        }

        page += 1;
      } while (page <= totalPages);

      if (kDebugMode) {
        debugPrint(
            '[WebBridge] ✅ Successfully fetched ${shops.length} total shops');
      }

      return shops;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[WebBridge] ❌ Error fetching shops: $e');
        debugPrint('[WebBridge] Stack trace: $stackTrace');
      }
      rethrow;
    }
  }

  /// Create order in warehouse backend
  ///
  /// POST /api/orders
  /// Body: {
  ///   customerId: int,
  ///   items: [{ productId: int, quantity: int }],
  ///   orderType?: 'Market' | 'Store',
  ///   paymentMethod?: 'Cash' | 'Credit' | 'BankTransfer' | 'Sales' | 'Padan',
  ///   userWeveToken?: string  // Optional: Weve authentication token from logged-in user
  /// }
  Future<Map<String, dynamic>> createOrder({
    required int customerId,
    required List<Map<String, dynamic>> items,
    String? orderType,
    String? paymentMethod,
    String? deliveryDate,
    int? creditTermDays,
    String? userWeveToken, // Weve token from logged-in user
  }) async {
    final body = await _postJson('orders', data: {
      'customerId': customerId,
      'items': items,
      if (orderType != null) 'orderType': orderType,
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
      if (deliveryDate != null) 'deliveryDate': deliveryDate,
      if (creditTermDays != null) 'creditTermDays': creditTermDays,
      if (userWeveToken != null)
        'userWeveToken': userWeveToken, // Pass user's Weve token
    });
    return _unwrapData(body);
  }

  /// Get monthly sales target/plan from backend
  ///
  /// GET /api/sales/monthly-target?year=2024&month=1
  /// Returns: { status: "success", data: { monthlyTarget: 30000000, year: 2024, month: 1 } }
  Future<Map<String, dynamic>> getMonthlyTarget({
    int? year,
    int? month,
  }) async {
    final now = DateTime.now();
    final queryParams = <String, dynamic>{
      'year': year ?? now.year,
      'month': month ?? now.month,
    };
    try {
      final body = await _getJson('sales/monthly-target', qp: queryParams);
      return _unwrapData(body);
    } catch (e) {
      // If endpoint doesn't exist, return default
      if (kDebugMode) {
        debugPrint(
            '[WebBridge] Monthly target endpoint not available, using default');
      }
      return {
        'monthlyTarget': 30000000.0, // Default 30M ₮
        'year': year ?? now.year,
        'month': month ?? now.month,
      };
    }
  }

  /// Set monthly sales target/plan in backend
  ///
  /// POST /api/sales/monthly-target
  /// Body: { year: 2024, month: 1, monthlyTarget: 30000000 }
  Future<Map<String, dynamic>> setMonthlyTarget({
    required int year,
    required int month,
    required double monthlyTarget,
  }) async {
    try {
      final body = await _postJson('sales/monthly-target', data: {
        'year': year,
        'month': month,
        'monthlyTarget': monthlyTarget,
      });
      return _unwrapData(body);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebBridge] Failed to set monthly target: $e');
      }
      rethrow;
    }
  }

  /// Get products for sale (with stock and pricing info)
  ///
  /// GET /api/products?forSale=true&hasStock=true
  /// Returns products that should be displayed on website for sales
  Future<List<Product>> getProductsForSale({
    bool hasStock = true,
    bool hasPrice = true,
    bool includeInactive = false, // Don't include inactive products for sale
  }) async {
    final allProducts =
        await fetchAllProducts(includeInactive: includeInactive);

    // Filter products that should be sold
    return allProducts.where((product) {
      // Only include active products for sale
      if (!includeInactive && (product.isActive == false)) return false;
      if (hasPrice && product.price <= 0) return false;
      if (hasStock && (product.stockQuantity ?? 0) <= 0) return false;
      return true;
    }).toList();
  }
}
