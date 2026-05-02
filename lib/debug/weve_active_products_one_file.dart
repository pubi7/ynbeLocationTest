import 'package:dio/dio.dart';

import '../config/api_config.dart';

typedef Json = Map<String, dynamic>;

/// Single-file reference for fetching **active** products only.
///
/// Backend endpoint used:
/// - GET /api/products
///
/// Note:
/// - If backend doesn't support filtering by `isActive`, this class filters
///   client-side using the returned `isActive` field.
class WeveActiveProductsOneFile {
  WeveActiveProductsOneFile({
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

  /// Fetch products and return only those with `isActive == true`.
  ///
  /// This mirrors the pagination style used by the app (`limit` + `page`).
  Future<List<Json>> fetchActiveProducts({
    int pageSize = 200,
    String? search,
  }) async {
    final items = <Json>[];
    var page = 1;
    var totalPages = 1;

    do {
      final qp = <String, dynamic>{
        'limit': pageSize,
        'page': page,
        if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      };

      final r = await _dio.get<Json>('products', queryParameters: qp);
      final data = _unwrapData(r.data);

      final rawProducts = (data['products'] as List?) ?? const [];
      for (final it in rawProducts) {
        if (it is Map) {
          final m = it.cast<String, dynamic>();
          if (m['isActive'] == true) items.add(m);
        }
      }

      final pagination = (data['pagination'] is Map)
          ? (data['pagination'] as Map).cast<String, dynamic>()
          : const <String, dynamic>{};
      totalPages = (pagination['totalPages'] as num?)?.toInt() ?? 1;
      page += 1;
    } while (page <= totalPages);

    return items;
  }

  Json _unwrapData(Json? body) {
    final b = body ?? const <String, dynamic>{};
    final data = b['data'];
    if (data is Map<String, dynamic>) return data;
    return b;
  }
}

