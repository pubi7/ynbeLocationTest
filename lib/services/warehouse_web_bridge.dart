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
      'stockQuantity': (p['stockQuantity'] is num) ? (p['stockQuantity'] as num).toInt() : null,
      'unitsPerBox': (p['unitsPerBox'] is num) ? (p['unitsPerBox'] as num).toInt() : null,
      'priceWholesale': p['priceWholesale']?.toString(),
      'priceRetail': p['priceRetail']?.toString(),
      'pricePerBox': p['pricePerBox']?.toString(),
      'netWeight': p['netWeight']?.toString(),
      'grossWeight': p['grossWeight']?.toString(),
      'categoryName': (p['category'] is Map) ? (p['category'] as Map)['nameMongolian']?.toString() : null,
      'supplierName': (p['supplier'] is Map) ? (p['supplier'] as Map)['name']?.toString() : null,
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
      'locationLatitude': (c['locationLatitude'] is num) ? (c['locationLatitude'] as num).toDouble() : null,
      'locationLongitude': (c['locationLongitude'] is num) ? (c['locationLongitude'] as num).toDouble() : null,
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
    if (code != null && (code == 502 || code == 503 || code == 504)) return true;
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError;
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final extra = err.requestOptions.extra;
    final attempt = (extra['retry_attempt'] as int?) ?? 0;
    if (attempt >= retries || !_shouldRetry(err)) {
      return handler.next(err);
    }

    final delay = retryDelays.length > attempt ? retryDelays[attempt] : retryDelays.last;
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
                connectTimeout: const Duration(seconds: 10),
                sendTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
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
          if (kDebugMode) debugPrint('[WebBridge] → ${options.method} ${options.uri}');
          handler.next(options);
        },
        onResponse: (resp, handler) {
          if (kDebugMode) debugPrint('[WebBridge] ← ${resp.statusCode} ${resp.requestOptions.uri}');
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
              debugPrint('[WebBridge] ✗ status=${e.response?.statusCode} body=${e.response?.data}');
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
    final status = body['status']?.toString();
    if (status != null && status != 'success') {
      throw Exception(body['message'] ?? 'Request failed');
    }
    final data = body['data'];
    if (data is Map) return data.cast<String, dynamic>();
    return body;
  }

  Future<Map<String, dynamic>> _getJson(String path, {Map<String, dynamic>? qp}) async {
    final r = await _dio.get<Map<String, dynamic>>(path, queryParameters: qp);
    return r.data ?? <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _postJson(String path, {Object? data}) async {
    final r = await _dio.post<Map<String, dynamic>>(path, data: data);
    return r.data ?? <String, dynamic>{};
  }

  Future<String> login({required String identifier, required String password}) async {
    final body = await _postJson(
      'auth/login',
      data: {'identifier': identifier, 'password': password},
    );
    final data = _unwrapData(body);
    final token = data['token']?.toString();
    if (token == null || token.isEmpty) {
      throw Exception(body['message'] ?? 'Token not returned from server');
    }
    setToken(token);
    await saveToken(token);
    return token;
  }

  Future<List<Product>> fetchAllProducts({int pageSize = 200}) async {
    final products = <Product>[];
    var page = 1;
    var totalPages = 1;

    do {
      final body = await _getJson('products', qp: {'limit': pageSize, 'page': page});
      final data = _unwrapData(body);
      final raw = (data['products'] as List?) ?? const [];
      final pagination = (data['pagination'] is Map) ? (data['pagination'] as Map).cast<String, dynamic>() : <String, dynamic>{};
      totalPages = (pagination['totalPages'] as num?)?.toInt() ?? 1;

      final extracted = await compute(_extractProductMaps, raw);
      for (final p in extracted) {
        final id = (p['id'] ?? '').toString();
        final name = (p['nameMongolian'] ?? p['nameEnglish'] ?? 'N/A').toString();
        final priceRaw = p['priceRetail'] ?? p['priceWholesale'] ?? p['pricePerBox'] ?? 0;
        final price = double.tryParse(priceRaw.toString()) ?? 0.0;

        products.add(
          Product(
            id: id,
            name: name,
            price: price,
            description: p['nameEnglish']?.toString(),
            category: p['categoryName']?.toString(),
            supplierName: p['supplierName']?.toString(),
            barcode: p['barcode']?.toString(),
            productCode: p['productCode']?.toString(),
            stockQuantity: p['stockQuantity'] as int?,
            unitsPerBox: p['unitsPerBox'] as int?,
            netWeight: double.tryParse((p['netWeight'] ?? '').toString()),
            grossWeight: double.tryParse((p['grossWeight'] ?? '').toString()),
            priceWholesale: double.tryParse((p['priceWholesale'] ?? '').toString()),
            priceRetail: double.tryParse((p['priceRetail'] ?? '').toString()),
            pricePerBox: double.tryParse((p['pricePerBox'] ?? '').toString()),
          ),
        );
      }

      page += 1;
    } while (page <= totalPages);

    return products;
  }

  Future<List<Shop>> fetchAllShops({int pageSize = 200}) async {
    final shops = <Shop>[];
    var page = 1;
    var totalPages = 1;

    do {
      final body = await _getJson('customers', qp: {'limit': pageSize, 'page': page});
      final data = _unwrapData(body);
      final customers = (data['customers'] as List?) ?? const [];
      final pagination = (data['pagination'] is Map) ? (data['pagination'] as Map).cast<String, dynamic>() : <String, dynamic>{};
      totalPages = (pagination['totalPages'] as num?)?.toInt() ?? 1;

      final extracted = await compute(_extractShopMaps, customers);
      for (final c in extracted) {
        final name = (c['name'] ?? 'N/A').toString();
        final district = (c['district'] ?? '').toString().trim();
        final address = (c['address'] ?? '').toString().trim();
        final detailedAddress = (c['detailedAddress'] ?? '').toString().trim();
        final fullAddress = [district, address, detailedAddress].where((s) => s.trim().isNotEmpty).join(', ');

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
            status: 'active',
            orders: const [],
            sales: const [],
            lastVisit: DateTime.now(),
          ),
        );
      }

      page += 1;
    } while (page <= totalPages);

    return shops;
  }
}

