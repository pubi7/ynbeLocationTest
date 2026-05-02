import 'package:dio/dio.dart';

import '../config/api_config.dart';

typedef Json = Map<String, dynamic>;

/// Single-file reference for "Weve site order flow" backend calls.
///
/// This mirrors the two key calls used by the app:
/// - POST   /api/orders
/// - PUT/PATCH /api/orders/:id/status
class WeveOrderFlowOneFile {
  WeveOrderFlowOneFile({
    required String accessToken,
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: ApiConfig.warehouseApiBaseUrl,
                headers: <String, dynamic>{
                  'Authorization': 'Bearer $accessToken',
                  'Content-Type': 'application/json',
                },
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 30),
              ),
            );

  final Dio _dio;

  /// Create order so it appears on Weve website/dashboard.
  ///
  /// Backend endpoint: POST /api/orders
  Future<Json> createOrder({
    required int customerId,
    required List<Json> items, // [{productId:int, quantity:int, unitPrice?:num}]
    String orderType = 'Store',
    String? paymentMethod,
    String? notes,
    String? deliveryDate,
    int? creditTermDays,
    bool allowInsufficientStock = false,
    String? userWeveToken,
  }) async {
    final payload = <String, dynamic>{
      'customerId': customerId,
      'items': items,
      'orderType': orderType,
      if (paymentMethod != null) 'paymentMethod': paymentMethod,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      if (deliveryDate != null && deliveryDate.trim().isNotEmpty)
        'deliveryDate': deliveryDate.trim(),
      if (creditTermDays != null) 'creditTermDays': creditTermDays,
      if (userWeveToken != null) 'userWeveToken': userWeveToken,
      'allowInsufficientStock': allowInsufficientStock,
    };

    final r = await _dio.post<Json>('orders', data: payload);
    return _unwrapData(r.data);
  }

  /// Update order status so Weve website reflects state changes.
  ///
  /// Tries common endpoints for compatibility:
  /// - PUT/PATCH /api/orders/:id/status
  /// - PUT/PATCH /api/orders/:id
  Future<Json> updateOrderStatus({
    required int orderId,
    required String status,
  }) async {
    final payload = <String, dynamic>{'status': status};
    final opts = Options(validateStatus: (c) => c != null && c < 500);

    Future<Response<Json>> _put(String path) =>
        _dio.put<Json>(path, data: payload, options: opts);
    Future<Response<Json>> _patch(String path) =>
        _dio.patch<Json>(path, data: payload, options: opts);

    bool _ok(int? c) => c != null && c >= 200 && c < 300;

    final attempts = <Future<Response<Json>> Function()>[
      () => _put('orders/$orderId/status'),
      () => _patch('orders/$orderId/status'),
      () => _put('orders/$orderId'),
      () => _patch('orders/$orderId'),
    ];

    Response<Json>? last;
    for (final f in attempts) {
      final r = await f();
      last = r;
      if (_ok(r.statusCode)) return _unwrapData(r.data);
    }

    throw DioException(
      requestOptions: last?.requestOptions ??
          RequestOptions(path: 'orders/$orderId/status'),
      response: last,
      type: DioExceptionType.badResponse,
      error:
          'Failed to update order status. Last status=${last?.statusCode} body=${last?.data}',
    );
  }

  Json _unwrapData(Json? body) {
    final b = body ?? const <String, dynamic>{};
    final data = b['data'];
    if (data is Map<String, dynamic>) return data;
    return b;
  }
}

