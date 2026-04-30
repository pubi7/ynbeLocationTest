import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'warehouse_tls_adapter_stub.dart'
    if (dart.library.io) 'warehouse_tls_adapter_io.dart' as warehouse_tls_adapter;
import '../models/product_model.dart';
import '../models/shop_model.dart';

/// Native дээр ApiConfig-оос base URL ирэхгүй үед Dio-д оруулах түр placeholder (.invalid DNS).
String _warehouseDioInitialBaseUrl() {
  final configured = ApiConfig.warehouseApiBaseUrl;
  if (configured.isNotEmpty) return configured;
  return 'http://backend-not-configured.invalid/api/';
}

// -------- Isolate-safe extraction (compute requires sendable types) --------

/// Ð‘Ð°Ñ€Ð°Ð°Ð½Ñ‹ Ò¯Ð»Ð´ÑÐ³Ð´Ð»Ð¸Ð¹Ð³ Ð¾Ð»Ð¾Ð½ Ñ„Ð¾Ñ€Ð¼Ð°Ñ‚Ð°Ð°Ñ Ð·Ð°Ð´Ð»Ð°Ñ… (num, string, stock, quantity, Ð³ÑÑ… Ð¼ÑÑ‚)
/// availableStock - backend-Ð¸Ð¹Ð½ Ð¸Ð´ÑÐ²Ñ…Ñ‚ÑÐ¹ Ð±Ð°Ð³Ñ†Ð°Ð°Ñ Ñ‚Ð¾Ð¾Ñ†ÑÐ¾Ð½ Ð±Ð¾Ð´Ð¸Ñ‚ Ò¯Ð»Ð´ÑÐ³Ð´ÑÐ» (Ð·Ó©Ð²ÑˆÓ©Ó©Ñ€Ó©Ð³Ð´Ó©Ð½Ó©)
int? _parseStockQuantity(Map<String, dynamic> p) {
  final v = p['availableStock'] ??
      p['stockQuantity'] ??
      p['stock'] ??
      p['quantity'] ??
      p['inventoryQuantity'] ??
      p['currentStock'];
  if (v == null) return null;
  if (v is num) return v.toInt();
  if (v is String) {
    final n = int.tryParse(v.trim());
    if (n != null && n >= 0) return n;
  }
  return null;
}

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
      'stockQuantity': _parseStockQuantity(
          p), // availableStock Ð±Ð¾Ð»Ð²Ð¾Ð» Ñ‚Ò¯Ò¯Ð½Ð¸Ð¹Ð³ Ð°ÑˆÐ¸Ð³Ð»Ð°Ð½Ð°
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
      // Warehouse API: products.default_price (see Prisma Product.defaultPrice)
      'defaultPrice': (p['defaultPrice'] is num)
          ? (p['defaultPrice'] as num).toDouble()
          : (p['defaultPrice']?.toString()),
      // Some APIs only expose a single price / unit price (not priceRetail, etc.)
      'price': (p['price'] is num)
          ? (p['price'] as num).toDouble()
          : (p['price']?.toString()),
      'unitPrice': (p['unitPrice'] is num)
          ? (p['unitPrice'] as num).toDouble()
          : (p['unitPrice']?.toString()),
      'salePrice': (p['salePrice'] is num)
          ? (p['salePrice'] as num).toDouble()
          : (p['salePrice']?.toString()),
      'basePrice': (p['basePrice'] is num)
          ? (p['basePrice'] as num).toDouble()
          : (p['basePrice']?.toString()),
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
      // НӨАТ-гүй үнэ эсэх (backend талбарууд)
      'priceExcludesVat': p['priceExcludesVat'],
      'priceIncludesVat': p['priceIncludesVat'],
      'isNetPrice': p['isNetPrice'],
      'vatIncluded': p['vatIncluded'],
      'categoryName': (p['category'] is Map)
          ? (p['category'] as Map)['nameMongolian']?.toString()
          : null,
      'supplierName': (p['supplier'] is Map)
          ? (p['supplier'] as Map)['name']?.toString()
          : null,
      // Product active status (default to true if not provided)
      'isActive': p['isActive'] ?? p['active'] ?? true,
      // Ð”ÑÐ»Ð³Ò¯Ò¯Ñ€ (customerType)-Ð°Ð°Ñ Ñ…Ð°Ð¼Ð°Ð°Ñ€Ð°Ñ… Ò¯Ð½Ñ - ProductPrice array from API
      'pricesByCustomerType': _extractPricesByCustomerType(p['prices']),
    });
  }
  return out;
}

Map<int, double>? _extractPricesByCustomerType(dynamic raw) {
  if (raw == null || raw is! List) return null;
  final result = <int, double>{};
  for (final item in raw) {
    if (item is! Map) continue;
    final m = item.cast<String, dynamic>();
    int? k;
    final ctId = m['customerTypeId'];
    if (ctId != null) {
      k = (ctId is num) ? ctId.toInt() : int.tryParse(ctId.toString());
    } else if (m['customerType'] is Map) {
      final cid = (m['customerType'] as Map)['id'];
      if (cid != null) {
        k = (cid is num) ? cid.toInt() : int.tryParse(cid.toString());
      }
    }
    final price =
        m['price'] ?? m['unitPrice'] ?? m['retailPrice'] ?? m['amount'];
    if (k == null || price == null) continue;
    final v =
        (price is num) ? price.toDouble() : double.tryParse(price.toString());
    if (v != null && v > 0) result[k] = v;
  }
  return result.isEmpty ? null : result;
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
      'registrationNumber': (c['registrationNumber'] ??
              c['companyRegistrationNumber'] ??
              c['regNo'] ??
              c['registration_no'] ??
              c['customerRegNo'])
          ?.toString(),
      'customerTypeId': (c['customerTypeId'] is num)
          ? (c['customerTypeId'] as num).toInt()
          : int.tryParse((c['customerTypeId'] ?? '').toString()),
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

/// Successful login: token + optional user from the login JSON (backup if `auth/profile` fails).
class WarehouseLoginResult {
  final String token;
  final Map<String, dynamic>? loginUser;

  const WarehouseLoginResult({required this.token, this.loginUser});
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
/// - GET  `etax/organization/:regno` -> eTax / getTinInfo (нэр, регистр, auth)
/// - POST `ebarimt/register/:orderId` -> POS баримт бүртгэсний дараах хариу (lottery, qrData, …)
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
                baseUrl: _warehouseDioInitialBaseUrl(),
                connectTimeout:
                    const Duration(seconds: 30), // Increased for slow networks
                sendTimeout:
                    const Duration(seconds: 30), // Increased for slow networks
                receiveTimeout: const Duration(
                    seconds: 60), // Increased for large responses
                headers: const {'Content-Type': 'application/json'},
              ),
            ) {
    if (ApiConfig.warehouseTlsInsecure && kDebugMode) {
      debugPrint(
        '[WebBridge] WAREHOUSE_TLS_INSECURE: TLS certificate verification disabled (dev/test only)',
      );
    }
    warehouse_tls_adapter.configureWarehouseDioTls(
      _dio,
      ApiConfig.warehouseTlsInsecure,
    );

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
            debugPrint('[WebBridge] â†’ ${options.method} ${options.uri}');
          handler.next(options);
        },
        onResponse: (resp, handler) {
          if (kDebugMode)
            debugPrint(
                '[WebBridge] â† ${resp.statusCode} ${resp.requestOptions.uri}');
          handler.next(resp);
        },
        onError: (e, handler) async {
          if (e.response?.statusCode == 401) {
            await clearToken();
            onUnauthorized?.call();
          }
          if (kDebugMode) {
            debugPrint('[WebBridge] âœ— ${e.type} ${e.requestOptions.uri}');
            if (e.response != null) {
              debugPrint(
                  '[WebBridge] âœ— status=${e.response?.statusCode} body=${e.response?.data}');
            } else {
              debugPrint('[WebBridge] âœ— message=${e.message}');
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
    if (s.isEmpty) return _warehouseDioInitialBaseUrl();

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
            '[WebBridge] âŒ Response status is not success: $status - $message');
      }
      throw Exception(message);
    }
    final data = body['data'];
    if (data is Map) {
      if (kDebugMode) {
        debugPrint('[WebBridge] âœ… Unwrapped data with keys: ${data.keys}');
      }
      return data.cast<String, dynamic>();
    }
    if (kDebugMode) {
      debugPrint(
          '[WebBridge] âš ï¸ No data field found, returning body as-is');
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
        debugPrint('[WebBridge] âŒ Error in _postJson for $path: $e');
        if (e is DioException) {
          debugPrint('[WebBridge] Error type: ${e.type}');
          debugPrint('[WebBridge] Status: ${e.response?.statusCode}');
          debugPrint('[WebBridge] Response data: ${e.response?.data}');
          debugPrint('[WebBridge] Request URL: ${e.requestOptions.uri}');

          // Provide specific error messages for connection issues
          if (e.type == DioExceptionType.connectionTimeout) {
            debugPrint(
                '[WebBridge] âš ï¸ Connection timeout - server may be unreachable or slow');
            debugPrint(
                '[WebBridge] âš ï¸ Check if server at ${e.requestOptions.uri} is running');
          } else if (e.type == DioExceptionType.sendTimeout) {
            debugPrint(
                '[WebBridge] âš ï¸ Send timeout - request took too long to send');
          } else if (e.type == DioExceptionType.receiveTimeout) {
            debugPrint(
                '[WebBridge] âš ï¸ Receive timeout - response took too long');
          } else if (e.type == DioExceptionType.connectionError) {
            debugPrint(
                '[WebBridge] âš ï¸ Connection error - cannot reach server');
            debugPrint(
                '[WebBridge] âš ï¸ Check network connection and server address');
          }
        }
      }
      rethrow;
    }
  }

  Map<String, dynamic>? _mapFromDynamic(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) return v;
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val));
    }
    return null;
  }

  Future<String> login(
      {required String identifier, required String password}) async {
    final r =
        await loginWithDetails(identifier: identifier, password: password);
    return r.token;
  }

  Future<WarehouseLoginResult> loginWithDetails(
      {required String identifier, required String password}) async {
    // Strategy:
    // - If identifier ends with @warehouse.com, must exist in backend (normal login only)
    // - Otherwise, try agent-login first (Weve site authentication), then fallback to normal login

    if (kDebugMode) {
      debugPrint('[WebBridge] ðŸ” Starting login for identifier: $identifier');
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
            debugPrint('[WebBridge] âŒ Login failed: $errorMsg');
          }
          throw Exception(errorMsg);
        }

        setToken(token);
        await saveToken(token);

        if (kDebugMode) {
          debugPrint('[WebBridge] âœ… Login successful for warehouse email');
        }

        return WarehouseLoginResult(
          token: token,
          loginUser: _mapFromDynamic(data['user']),
        );
      } catch (e) {
        if (kDebugMode) {
          debugPrint('[WebBridge] âŒ Warehouse login error: $e');
          if (e is DioException) {
            debugPrint('[WebBridge] Status: ${e.response?.statusCode}');
            debugPrint('[WebBridge] Response: ${e.response?.data}');
            debugPrint('[WebBridge] Error type: ${e.type}');

            // Provide specific guidance for connection issues
            if (e.type == DioExceptionType.connectionTimeout ||
                e.type == DioExceptionType.connectionError) {
              debugPrint('[WebBridge] âš ï¸ CONNECTION ERROR DETECTED');
              debugPrint('[WebBridge] Server URL: ${_dio.options.baseUrl}');
              debugPrint('[WebBridge] Full URL: ${e.requestOptions.uri}');
              debugPrint('[WebBridge] Dio message: ${e.message}');
              debugPrint('[WebBridge] Underlying error: ${e.error}');
              debugPrint('[WebBridge]');
              debugPrint('[WebBridge] Possible issues:');
              debugPrint('[WebBridge] 1. Server is not running');
              debugPrint('[WebBridge] 2. Server URL is incorrect');
              debugPrint('[WebBridge] 3. Network connectivity problem');
              if (kIsWeb) {
                debugPrint('[WebBridge] 4. CORS not enabled on server');
                debugPrint('[WebBridge]    â†’ Server needs CORS headers:');
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
                debugPrint(
                    '[WebBridge] âœ… Agent ID Ñ…Ð°Ð´Ð³Ð°Ð»Ð°Ð³Ð´Ð»Ð°Ð°: $agentIdInt');
              }
            }
          }
        }

        if (kDebugMode) {
          debugPrint('[WebBridge] âœ… Agent-login successful');
        }

        return WarehouseLoginResult(
          token: agentToken,
          loginUser: _mapFromDynamic(agentData['agent']) ??
              _mapFromDynamic(agentData['user']),
        );
      } else {
        if (kDebugMode) {
          debugPrint(
              '[WebBridge] âš ï¸ Agent-login succeeded but no token received');
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
              errorMessage.toLowerCase().contains('Ð±Ò¯Ñ€Ñ‚Ð³ÑÐ»Ð³Ò¯Ð¹') ||
              errorMessage.toLowerCase().contains('user not found')) {
            if (kDebugMode) {
              debugPrint('[WebBridge] âŒ User not registered in Weve site');
            }
            throw Exception('USER_NOT_REGISTERED');
          } else {
            // For agent-login, 401/403 usually means not registered
            if (kDebugMode) {
              debugPrint('[WebBridge] âŒ User not registered (401/403)');
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
          debugPrint('[WebBridge] âŒ Normal login failed: $errorMsg');
        }
        throw Exception(errorMsg);
      }

      setToken(token);
      await saveToken(token);

      if (kDebugMode) {
        debugPrint('[WebBridge] âœ… Normal login successful');
      }

      return WarehouseLoginResult(
        token: token,
        loginUser: _mapFromDynamic(data['user']),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebBridge] âŒ Normal login error: $e');
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
            '[WebBridge] ðŸ” Testing connection to ${_dio.options.baseUrl}');
      }

      // Use a shorter timeout for connection test (default 5 seconds)
      final testTimeout = timeout ?? const Duration(seconds: 5);
      final testDio = Dio(BaseOptions(
        baseUrl: _dio.options.baseUrl,
        connectTimeout: testTimeout,
        receiveTimeout: testTimeout,
      ));
      warehouse_tls_adapter.configureWarehouseDioTls(
        testDio,
        ApiConfig.warehouseTlsInsecure,
      );

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
          debugPrint('[WebBridge] âœ… Connection test successful');
        }
        return true;
      } catch (e) {
        // If we get 401/403, server is reachable but we're not authenticated
        if (e is DioException && e.response != null) {
          final status = e.response?.statusCode;
          if (status == 401 || status == 403) {
            if (kDebugMode) {
              debugPrint(
                  '[WebBridge] âœ… Server is reachable (got $status - authentication required)');
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
                '[WebBridge] âœ… Connection test successful (root endpoint)');
          }
          return true;
        } catch (_) {
          rethrow;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WebBridge] âŒ Connection test failed: $e');
        if (e is DioException) {
          debugPrint('[WebBridge] Error type: ${e.type}');
          debugPrint('[WebBridge] URL: ${e.requestOptions.uri}');
          if (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.connectionError) {
            debugPrint(
                '[WebBridge] âš ï¸ Cannot reach server at ${_dio.options.baseUrl}');
            debugPrint('[WebBridge] âš ï¸ Please check:');
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

      // If Weve endpoint returns an empty list, fall back to the main customers
      // endpoint (optionally unfiltered via allShops=true) so the UI still works.
      if (stores.isEmpty) {
        return await fetchAllShops();
      }

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
            customerTypeId: (s['customerTypeId'] as int?),
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

  /// Helper method to extract primary price (retail > wholesale > perBox,
  /// then generic API fields, then [prices] → pricesByCustomerType).
  double _extractPrimaryPrice(Map<String, dynamic> p) {
    final retail = _parsePrice(p['priceRetail']);
    if (retail != null && retail > 0) return retail;

    final wholesale = _parsePrice(p['priceWholesale']);
    if (wholesale != null && wholesale > 0) return wholesale;

    final perBox = _parsePrice(p['pricePerBox']);
    if (perBox != null && perBox > 0) return perBox;

    final defaultPrice = _parsePrice(p['defaultPrice']);
    if (defaultPrice != null && defaultPrice > 0) return defaultPrice;

    final single = _parsePrice(p['price']) ??
        _parsePrice(p['unitPrice']) ??
        _parsePrice(p['salePrice']) ??
        _parsePrice(p['basePrice']);
    if (single != null && single > 0) return single;

    final byType = p['pricesByCustomerType'] as Map<int, double>?;
    if (byType != null && byType.isNotEmpty) {
      final positives = byType.values.where((v) => v > 0).toList()..sort();
      if (positives.isNotEmpty) return positives.first;
    }

    return 0.0;
  }

  /// API эсвэл [ApiConfig.warehousePricesExcludeVat]: үнэ НӨАТ-гүй бол net эсэх.
  bool _readPriceExcludesVat(Map<String, dynamic> p) {
    if (p['priceExcludesVat'] == true || p['isNetPrice'] == true) {
      return true;
    }
    if (p['priceIncludesVat'] == true ||
        p['vatIncluded'] == true ||
        p['grossPrice'] == true) {
      return false;
    }
    return ApiConfig.warehousePricesExcludeVat;
  }

  /// Helper method to convert extracted product map to Product model
  Product _mapToProduct(Map<String, dynamic> p) {
    final id = (p['id'] ?? '').toString();
    final name = (p['nameMongolian'] ?? p['nameEnglish'] ?? 'N/A').toString();
    final excludesVat = _readPriceExcludesVat(p);
    final price = _extractPrimaryPrice(p);

    final discountPercent =
        int.tryParse((p['discountPercent'] ?? '').toString());
    final promotionText = (p['promotionText'] ?? '').toString().trim();

    final byType = p['pricesByCustomerType'] as Map<int, double>?;
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
      stockQuantity: _parseStockQuantity(p),
      unitsPerBox: p['unitsPerBox'] as int?,
      netWeight: _parsePrice(p['netWeight']),
      grossWeight: _parsePrice(p['grossWeight']),
      priceWholesale: _parsePrice(p['priceWholesale']),
      priceRetail: _parsePrice(p['priceRetail']),
      pricePerBox: _parsePrice(p['pricePerBox']),

      /// Backend-ийн `prices` массив — серверийн утгыг хувиргалтгүй хадгална.
      pricesByCustomerType: byType,
      unitPriceExcludesVat: excludesVat,
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
          '[WebBridge] ðŸš€ Starting product fetch (pageSize: $pageSize, includeInactive: $includeInactive)');
    }

    try {
      do {
        if (kDebugMode) {
          debugPrint(
              '[WebBridge] ðŸ“„ Fetching products page $page/$totalPages...');
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
                '[WebBridge] ðŸ“¦ Found ${rawProducts.length} products in page $page');
          }

          // Extract pagination info
          final pagination = (data['pagination'] is Map)
              ? (data['pagination'] as Map).cast<String, dynamic>()
              : <String, dynamic>{};
          totalPages = (pagination['totalPages'] as num?)?.toInt() ?? 1;

          if (rawProducts.isEmpty && page < totalPages && kDebugMode) {
            debugPrint(
                '[WebBridge] âš ï¸ Empty page $page but totalPages is $totalPages');
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
          }

          page += 1;
          retryCount = 0; // Reset retry count on success
        } catch (e) {
          retryCount++;
          if (kDebugMode) {
            debugPrint(
                '[WebBridge] âš ï¸ Error fetching page $page (attempt $retryCount/$maxRetries): $e');
          }

          // Retry logic for transient errors
          if (retryCount < maxRetries && _isRetryableError(e)) {
            final delayMs = retryCount * 1000; // Exponential backoff
            if (kDebugMode) {
              debugPrint(
                  '[WebBridge] ðŸ”„ Retrying page $page after ${delayMs}ms...');
            }
            await Future.delayed(Duration(milliseconds: delayMs));
            continue; // Retry same page
          } else {
            // Max retries reached or non-retryable error
            if (kDebugMode) {
              debugPrint(
                  '[WebBridge] âŒ Failed to fetch page $page after $retryCount attempts');
            }
            // Return partial results if available
            if (products.isNotEmpty) {
              if (kDebugMode) {
                debugPrint(
                    '[WebBridge] âš ï¸ Returning ${products.length} products fetched so far (page $page failed)');
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
            '[WebBridge] âœ… Successfully fetched ${products.length} total products from $totalPages pages');
        if (products.isNotEmpty) {
          final productsWithPrice = products.where((p) => p.price > 0).length;
          final withoutPrice = products.length - productsWithPrice;
          debugPrint(
              '[WebBridge] Product summary: ${products.length} total, $productsWithPrice with price > 0, $withoutPrice without price');
        }
      }

      return products;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[WebBridge] âŒ Fatal error fetching products: $e');
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
        final body = await _getJson('customers',
            qp: {'limit': pageSize, 'page': page, 'allShops': 'true'});

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
              customerTypeId: (c['customerTypeId'] as int?),
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
            '[WebBridge] âœ… Successfully fetched ${shops.length} total shops');
      }

      return shops;
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[WebBridge] âŒ Error fetching shops: $e');
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
    String? notes,
    String? deliveryDate,
    int? creditTermDays,
    String? userWeveToken, // Weve token from logged-in user
    bool allowInsufficientStock =
        false, // Ò®Ð»Ð´ÑÐ³Ð´ÑÐ» Ñ…Ò¯Ñ€ÑÐ»Ñ†ÑÑ…Ð³Ò¯Ð¹ Ñ‡ Ð·Ð°Ñ…Ð¸Ð°Ð»Ð³Ð° Ò¯Ò¯ÑÐ³ÑÑ…
  }) async {
    final body = await _postJson('orders', data: {
      'customerId': customerId,
      'items': items,
      if (orderType != null) 'orderType': orderType,
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (deliveryDate != null) 'deliveryDate': deliveryDate,
      if (creditTermDays != null) 'creditTermDays': creditTermDays,
      if (userWeveToken != null)
        'userWeveToken': userWeveToken, // Pass user's Weve token
      'allowInsufficientStock': allowInsufficientStock,
    });
    return _unwrapData(body);
  }

  /// Update order with getTinInfo data (TIN, reg, org name) - Ð‘Ð°Ð¹Ð³ÑƒÑƒÐ»Ð³Ð° ÑÐ¾Ð½Ð³Ð¾ÑÐ¾Ð½ Ò¯ÐµÐ´
  /// PATCH /api/orders/{id}/ebarimt-info
  /// GET /api/etax/organization/:regno — Web-тай ижил (auth), ихэнхдээ 7 оронтой регистр.
  Future<Map<String, dynamic>> getEtaxOrganization(String regno) async {
    final clean = regno.replaceAll(RegExp(r'[\s\-]'), '');
    if (clean.isEmpty) {
      throw ArgumentError('regno хоосон');
    }
    final body = await _getJson('etax/organization/$clean');
    return _unwrapData(body);
  }

  /// POST /api/ebarimt/register/:orderId — `barimt.ts` POST /rest/receipt-ийн дараах lottery зэргийг буцаадаг.
  Future<Map<String, dynamic>> ebarimtRegisterOrder({
    required int orderId,
    Map<String, dynamic>? data,
  }) async {
    final body = await _postJson(
      'ebarimt/register/$orderId',
      data: data ?? const <String, dynamic>{},
    );
    return _unwrapData(body);
  }

  /// GET /api/orders/{id}
  Future<Map<String, dynamic>> getOrderById(int orderId) async {
    final body = await _getJson('orders/$orderId');
    return _unwrapData(body);
  }

  /// PUT /api/orders/{id}/ebarimt — шууд POS-оос ирсэн ДДТД-г хадгалах
  Future<Map<String, dynamic>> putOrderEbarimt({
    required int orderId,
    required String ebarimtId,
    required String ebarimtBillId,
    String? ebarimtDate,
    String? ebarimtReceiptType,
  }) async {
    final r = await _dio.put<Map<String, dynamic>>(
      'orders/$orderId/ebarimt',
      data: {
        'ebarimtId': ebarimtId,
        'ebarimtBillId': ebarimtBillId,
        if (ebarimtDate != null && ebarimtDate.isNotEmpty)
          'ebarimtDate': ebarimtDate,
        if (ebarimtReceiptType != null && ebarimtReceiptType.isNotEmpty)
          'ebarimtReceiptType': ebarimtReceiptType,
      },
    );
    return _unwrapData(r.data ?? <String, dynamic>{});
  }

  /// PATCH order status so web (Weve) reflects mobile state changes.
  ///
  /// Tries multiple common endpoints for compatibility:
  /// - PATCH /api/orders/:id              { status }
  /// - PATCH /api/orders/:id/status       { status }
  /// - PUT   /api/orders/:id              { status }
  /// - PUT   /api/orders/:id/status       { status }
  Future<Map<String, dynamic>> updateOrderStatus({
    required int orderId,
    required String status,
  }) async {
    final payload = {'status': status};

    // Зарим backend дээр PATCH /orders/:id нь "full update" validation-тай байдаг тул
    // {status} гэсэн payload-оор 400 буцааж болно. Тийм үед дараагийн endpoint руу шилжинэ.
    Options _opts() => Options(validateStatus: (code) => code != null && code < 500);

    Future<Response<Map<String, dynamic>>> _patch(String path) =>
        _dio.patch<Map<String, dynamic>>(path, data: payload, options: _opts());
    Future<Response<Map<String, dynamic>>> _put(String path) =>
        _dio.put<Map<String, dynamic>>(path, data: payload, options: _opts());

    Map<String, dynamic> _ok(Response<Map<String, dynamic>> r) =>
        _unwrapData(r.data ?? <String, dynamic>{});

    bool _isSuccess(int? c) => c != null && c >= 200 && c < 300;

    final attempts = <Future<Response<Map<String, dynamic>>> Function()>[
      () => _put('orders/$orderId/status'), // canonical in this backend
      () => _patch('orders/$orderId/status'),
      () => _put('orders/$orderId'),
      () => _patch('orders/$orderId'),
    ];

    Response<Map<String, dynamic>>? last;
    for (final f in attempts) {
      final r = await f();
      last = r;
      if (_isSuccess(r.statusCode)) return _ok(r);
      // ignore 400/404/405 etc and try next
    }

    throw DioException(
      requestOptions: last?.requestOptions ?? RequestOptions(path: 'orders/$orderId/status'),
      response: last,
      type: DioExceptionType.badResponse,
      error: 'Failed to update order status. Last status=${last?.statusCode} body=${last?.data}',
    );
  }

  /// POST /api/ebarimt/return/:orderId — POS баримт цуцлах, нөөц сэргээх, захиалга Cancelled.
  Future<Map<String, dynamic>> ebarimtReturnOrder({
    required int orderId,
    String? reason,
  }) async {
    final body = await _postJson(
      'ebarimt/return/$orderId',
      data: {
        if (reason != null && reason.trim().isNotEmpty) 'reason': reason.trim(),
      },
    );
    return _unwrapData(body);
  }

  Future<Map<String, dynamic>> updateOrderEbarimtInfo({
    required int orderId,
    required String tin,
    required String regNo,
    String? orgName,
  }) async {
    final body = await _dio.patch<Map<String, dynamic>>(
      'orders/$orderId/ebarimt-info',
      data: {
        'ebarimtTin': tin,
        'ebarimtRegNo': regNo,
        if (orgName != null && orgName.isNotEmpty) 'ebarimtOrgName': orgName,
      },
    );
    final data = body.data ?? <String, dynamic>{};
    return _unwrapData(data);
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
    final y = year ?? now.year;
    final m = month ?? now.month;
    final queryParams = <String, dynamic>{'year': y, 'month': m};
    try {
      // Хуучин серверт зам байхгүй үед 404 гарч Dio бүтэн алдаа хэвлэдэг тул 404-ийг шууд барина.
      final r = await _dio.get<Map<String, dynamic>>(
        'sales/monthly-target',
        queryParameters: queryParams,
        options: Options(
          validateStatus: (code) =>
              code != null && ((code >= 200 && code < 300) || code == 404),
        ),
      );
      if (r.statusCode == 404) {
        if (kDebugMode) {
          debugPrint(
            '[WebBridge] sales/monthly-target: 404 — зам байхгүй, default ашиглана',
          );
        }
        return {
          'monthlyTarget': 30000000.0,
          'year': y,
          'month': m,
        };
      }
      final body = r.data ?? <String, dynamic>{};
      return _unwrapData(body);
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
            '[WebBridge] Monthly target endpoint not available, using default: $e');
      }
      return {
        'monthlyTarget': 30000000.0,
        'year': y,
        'month': m,
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
