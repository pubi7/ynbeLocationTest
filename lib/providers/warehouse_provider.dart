import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/product_model.dart';
import '../models/shop_model.dart';
import '../services/sugalaanii_dugaar.dart';
import '../services/warehouse_web_bridge.dart';
import 'auth_provider.dart';
import '../utils/product_active_utils.dart';
import '../utils/warehouse_agent_shop_identity_one_file.dart';

class WarehouseProvider extends ChangeNotifier {
  final WarehouseWebBridge _bridge;

  bool _connected = false;
  bool _loading = false;
  String? _error;

  String? _token;
  List<Product> _products = [];
  List<Shop> _shops = [];

  WarehouseProvider({WarehouseWebBridge? bridge})
      : _bridge = bridge ?? WarehouseWebBridge() {
    // Auto logout when backend returns 401 (token expired/invalid)
    _bridge.onUnauthorized = () async {
      await disconnect();
    };
    _init();
  }

  bool get connected => _connected;
  bool get isLoading => _loading;
  String? get error => _error;
  List<Product> get products => _products;
  List<Shop> get shops => _shops;
  String get apiBaseUrl => _bridge.apiBaseUrl;

  /// Expose the authenticated Dio instance for other providers (e.g., OrderProvider)
  Dio get dio => _bridge.dio;

  Future<void> _init() async {
    final savedBaseUrl = await _bridge.loadApiBaseUrl();
    if (savedBaseUrl != null && savedBaseUrl.isNotEmpty) {
      await _bridge.setApiBaseUrl(savedBaseUrl);
    }
    _token = await _bridge.loadToken();
    _connected = _token != null && _token!.isNotEmpty;
    notifyListeners();
  }

  Future<void> updateApiBaseUrl(String input) async {
    // Prevent rapid API URL changes that could cause issues
    if (_loading) {
      debugPrint('Already loading, skipping API URL update');
      return;
    }
    final effective = ApiConfig.allowWarehouseUrlOverride
        ? input
        : ApiConfig.backendServerUrl;
    await _bridge.setApiBaseUrl(effective);
    await _bridge.saveApiBaseUrl(effective);
    notifyListeners();
  }

  /// Connect by making a fresh login call (legacy method).
  Future<bool> connect(
      {required String identifier,
      required String password,
      AuthProvider? authProvider}) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final token =
          await _bridge.login(identifier: identifier, password: password);
      _token = token;

      // Fetch user profile and update AuthProvider (with delay to prevent rate limiting)
      if (authProvider != null) {
        await _fetchAndUpdateProfile(authProvider, identifier);
      }

      _connected = true;
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      // Handle 429 error specifically
      if (e is DioException && e.response?.statusCode == 429) {
        _error = 'Хэт олон хүсэлт илгээсэн. Түр хүлээгээд дахин оролдоно уу.';
      } else {
        _error = e.toString();
      }
      _connected = false;
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Connect using an existing token (e.g. from MobileUserLoginProvider).
  /// This avoids a second login API call and uses the same user session.
  ///
  /// [fetchProfile]: false бол `GET auth/profile` дахин дуудахгүй — [MobileUserLoginProvider]
  /// аль хэдийн профайл татсан үед нэвтрэхийг хурдан болгоно.
  Future<bool> connectWithExistingToken({
    AuthProvider? authProvider,
    bool fetchProfile = true,
  }) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // The shared bridge already has the token set by MobileUserLoginProvider
      _token = await _bridge.loadToken();

      if (_token == null || _token!.isEmpty) {
        throw Exception('No token available');
      }

      // Make sure the token is set on the Dio instance
      _bridge.setToken(_token!);

      if (fetchProfile && authProvider != null) {
        await _fetchAndUpdateProfile(authProvider, '');
      }

      _connected = true;
      _loading = false;
      if (kDebugMode) {
        debugPrint(
            '[WarehouseProvider] [ok] Connected with existing token (no double login)');
      }
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WarehouseProvider] [err] connectWithExistingToken failed: $e');
      }
      _error = e.toString();
      _connected = false;
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Helper to fetch user profile and update AuthProvider
  Future<void> _fetchAndUpdateProfile(
      AuthProvider authProvider, String fallbackEmail) async {
    try {
      final profileData = await _bridge.getProfile();
      final rawUser = profileData['user'] ?? profileData['employee'];
      final Map<String, dynamic>? userData;
      if (rawUser is Map) {
        userData = rawUser.cast<String, dynamic>();
      } else if (profileData.isNotEmpty) {
        userData = profileData;
      } else {
        userData = null;
      }
      if (userData != null) {
        final agentIdInt =
            WarehouseAgentShopIdentity.parseAgentIdFromProfileOrUserMap(
                userData);
        if (agentIdInt != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt(WarehouseAgentShopIdentity.prefsAgentIdKey,
              agentIdInt);
          if (kDebugMode) {
            debugPrint(
                '[WarehouseProvider] [ok] Agent ID saved: $agentIdInt');
          }
        }

        await authProvider.updateFromBackend(
          id: (userData['id'] ?? '').toString(),
          name: userData['displayName']?.toString() ??
              userData['name']?.toString() ??
              'User',
          email: userData['email']?.toString() ?? fallbackEmail,
          role: userData['roleDisplay']?.toString().toLowerCase() ??
              userData['role']?.toString().toLowerCase() ??
              'user',
        );
      } else {
        if (kDebugMode) {
          debugPrint(
              '[WarehouseProvider] [warn] Profile payload missing user: $profileData');
        }
      }
    } catch (e) {
      // If profile fetch fails, continue with connection
      debugPrint('Failed to fetch profile: $e');
    }
  }

  Future<void> disconnect() async {
    _loading = true;
    notifyListeners();
    await _bridge.clearToken();
    _token = null;
    _connected = false;
    _products = [];
    _shops = [];
    _loading = false;
    notifyListeners();
  }

  Future<void> refreshProducts({
    bool includeInactive = false,
    bool excludeZeroStock = false,
  }) async {
    if (!_connected) {
      if (kDebugMode)
        debugPrint(
            '[WarehouseProvider] [warn] Not connected, skipping product refresh');
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      if (kDebugMode) {
        debugPrint('[WarehouseProvider] product refresh...');
      }
      final fetched =
          await _bridge.fetchAllProducts(includeInactive: includeInactive);
      var next = fetched;
      // Backend may ignore includeInactive; enforce active-only on mobile.
      if (!includeInactive) {
        next = next.where((p) => isProductActive(p)).toList();
      }
      if (excludeZeroStock) {
        next = next.where((p) => (p.stockQuantity ?? 0) > 0).toList();
      }
      _products = next;
      if (kDebugMode) {
        final inactive =
            _products.where((p) => !isProductActive(p)).length;
        final active = _products.length - inactive;
        debugPrint(
          '[WarehouseProvider] products: API rows=${fetched.length}, '
          'after filters=${_products.length} '
          '(activeOnly=${!includeInactive} zeroStockExcluded=$excludeZeroStock)',
        );
        debugPrint(
            '[WarehouseProvider] [ok] list size=${_products.length} (active=$active inactive=$inactive)');
        if (_products.isNotEmpty) {
          final withPrice = _products.where((p) => p.price > 0).length;
          final withStock =
              _products.where((p) => (p.stockQuantity ?? 0) > 0).length;
          debugPrint(
              '[WarehouseProvider] stats: withPrice=$withPrice withStock=$withStock');
          debugPrint(
              '[WarehouseProvider] first: ${_products.first.name} price=${_products.first.price}');
          final firstInactive = _products
              .cast<Product?>()
              .firstWhere((p) => p != null && !isProductActive(p),
                  orElse: () => null);
          if (firstInactive != null) {
            debugPrint(
                '[WarehouseProvider] example inactive: ${firstInactive.name} id=${firstInactive.id}');
          }
        } else {
          debugPrint('[WarehouseProvider] [warn] No products after filters');
        }
      }
      _loading = false;
      notifyListeners();
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        if (kDebugMode) {
          debugPrint('[WarehouseProvider] 401 Unauthorized - disconnecting');
        }
        await disconnect();
        return;
      }
      // Handle 429 error specifically
      if (e is DioException && e.response?.statusCode == 429) {
        _error = 'Хэт олон хүсэлт илгээсэн. Түр хүлээгээд дахин оролдоно уу.';
      } else {
        final errorMsg = e.toString();
        if (kDebugMode) {
          debugPrint(
              '[WarehouseProvider] [err] Error fetching products: $errorMsg');
          if (e is DioException) {
            debugPrint('[WarehouseProvider] Status: ${e.response?.statusCode}');
            debugPrint('[WarehouseProvider] Response: ${e.response?.data}');
          }
        }
        _error =
            'Барааны мэдээлэл авахад алдаа гарлаа: ${e is DioException ? (e.response?.data?['message'] ?? errorMsg) : errorMsg}';
      }
      _loading = false;
      notifyListeners();
    }
  }

  /// Нэвтрэх дараах нэг удаагийн ачаалал: бараа + дэлгүүр **зэрэгцээ** (нэг `_loading` мөргөлдөөнгүй).
  Future<void> refreshCatalogAfterLogin({
    bool includeInactiveProducts = false,
    int shopPageSize = 200,
  }) async {
    if (!_connected) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _bridge.fetchAllProducts(includeInactive: includeInactiveProducts),
        _bridge.fetchAllShops(pageSize: shopPageSize),
      ]);
      final fetched = results[0] as List<Product>;
      final shopList = results[1] as List<Shop>;

      var nextProducts = fetched;
      if (!includeInactiveProducts) {
        nextProducts = nextProducts.where((p) => isProductActive(p)).toList();
      }
      _products = nextProducts;
      _shops = shopList;

      if (kDebugMode) {
        debugPrint(
          '[WarehouseProvider] login catalog: products=${_products.length} shops=${_shops.length}',
        );
      }
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        if (kDebugMode) {
          debugPrint('[WarehouseProvider] 401 Unauthorized - disconnecting');
        }
        await disconnect();
        return;
      }
      if (e is DioException && e.response?.statusCode == 429) {
        _error = 'Хэт олон хүсэлт илгээсэн. Түр хүлээгээд дахин оролдоно уу.';
      } else {
        final errorMsg = e.toString();
        if (kDebugMode) {
          debugPrint('[WarehouseProvider] [err] refreshCatalogAfterLogin: $errorMsg');
        }
        _error =
            'Бараа/дэлгүүрийн мэдээлэл авахад алдаа: ${e is DioException ? (e.response?.data?['message'] ?? errorMsg) : errorMsg}';
      }
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshShops(
      {int pageSize = 200, AuthProvider? authProvider}) async {
    if (!_connected) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // GET /api/customers — `forAllAgents` + `includeAllCustomers` query (bridge)
      // нэмэгдсэн; бүх дэлгүүрийг авахын тулд backend эдгээр түлхүүрийг дэмжих ёстой.
      _shops = await _bridge.fetchAllShops(pageSize: pageSize);

      if (kDebugMode) {
        debugPrint(
            '[WarehouseProvider] [ok] Fetched ${_shops.length} shops (customers list)');
        if (_shops.isNotEmpty) {
          debugPrint(
              '[WarehouseProvider] First shop: ${_shops.first.name} - Address: ${_shops.first.address}');
        }
      }
      _loading = false;
      notifyListeners();
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        await disconnect();
        return;
      }
      // Handle 429 error specifically
      if (e is DioException && e.response?.statusCode == 429) {
        _error = 'Хэт олон хүсэлт илгээсэн. Түр хүлээгээд дахин оролдоно уу.';
      } else {
        final errorMsg = e.toString();
        if (kDebugMode) {
          debugPrint('[WarehouseProvider] [err] Error fetching shops: $errorMsg');
          if (e is DioException) {
            debugPrint('[WarehouseProvider] Status: ${e.response?.statusCode}');
            debugPrint('[WarehouseProvider] Response: ${e.response?.data}');
          }
        }
        _error =
            'Дэлгүүрийн мэдээлэл авахад алдаа гарлаа: ${e is DioException ? (e.response?.data?['message'] ?? errorMsg) : errorMsg}';
      }
      _loading = false;
      notifyListeners();
    }
  }

  /// Create order in warehouse backend
  Future<Map<String, dynamic>> createOrder({
    required int customerId,
    required List<Map<String, dynamic>> items,
    String? orderType,
    String? paymentMethod,
    String? notes,
    String? deliveryDate,
    String? orderAcceptanceDate,
    int? creditTermDays,
    bool allowInsufficientStock =
        false, // Үлдэгдэл хүрэлцэхгүй ч захиалга үүсгэх
  }) async {
    if (!_connected) {
      throw Exception('Not connected to warehouse backend');
    }

    try {
      return await _bridge.createOrder(
        customerId: customerId,
        items: items,
        orderType: orderType,
        paymentMethod: paymentMethod,
        notes: notes,
        deliveryDate: deliveryDate,
        orderAcceptanceDate: orderAcceptanceDate,
        creditTermDays: creditTermDays,
        allowInsufficientStock: allowInsufficientStock,
      );
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        await disconnect();
      }
      rethrow;
    }
  }

  /// Update order with getTinInfo data (TIN, reg, org name) - Weve website дээр харуулах
  Future<void> updateOrderEbarimtInfo({
    required int orderId,
    required String tin,
    required String regNo,
    String? orgName,
  }) async {
    if (!_connected) return;
    try {
      await _bridge.updateOrderEbarimtInfo(
        orderId: orderId,
        tin: tin,
        regNo: regNo,
        orgName: orgName,
      );
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        await disconnect();
      }
      rethrow;
    }
  }

  /// GET /api/etax/organization/:regno — байгууллагын нэр (getTinInfo дэлгэрэнгүй). Алдаа гарвал null.
  Future<Map<String, dynamic>?> tryGetEtaxOrganization(String regno) async {
    if (!_connected) return null;
    try {
      return await _bridge.getEtaxOrganization(regno);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WarehouseProvider] ETax organization: $e');
      }
      return null;
    }
  }

  /// POST /api/ebarimt/return/:orderId — баримт буцаах (POS + нөөц + цуцлах).
  Future<Map<String, dynamic>> ebarimtReturnOrder({
    required int orderId,
    String? reason,
  }) async {
    if (!_connected) {
      throw Exception('Not connected to warehouse backend');
    }
    try {
      return await _bridge.ebarimtReturnOrder(
        orderId: orderId,
        reason: reason,
      );
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        await disconnect();
      }
      rethrow;
    }
  }

  /// POST /api/orders/:id/ebarimt-return-done — mark returned & restock.
  Future<Map<String, dynamic>> ebarimtReturnDone({
    required int orderId,
    required String returnId,
  }) async {
    if (!_connected) {
      throw Exception('Not connected to warehouse backend');
    }
    try {
      return await _bridge.ebarimtReturnDone(orderId: orderId, returnId: returnId);
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        await disconnect();
      }
      rethrow;
    }
  }

  /// POST /api/ebarimt/register/:orderId — POS-оос ирсэн lottery зэргийг буцаадаг хариу. Алдаа гарвал null.
  Future<Map<String, dynamic>?> tryEbarimtRegisterOrder(
    int orderId, {
    Map<String, dynamic>? data,
  }) async {
    if (!_connected) return null;
    return SugalaaniiDugaar.tryEbarimtRegisterOrder(
      _bridge,
      orderId,
      data: data,
      onUnauthorized: disconnect,
    );
  }

  /// Update order status so it reflects on Weve website.
  Future<Map<String, dynamic>> updateOrderStatus({
    required int orderId,
    required String status,
  }) async {
    if (!_connected) {
      throw Exception('Not connected to warehouse backend');
    }
    try {
      return await _bridge.updateOrderStatus(orderId: orderId, status: status);
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        await disconnect();
      }
      rethrow;
    }
  }

  /// Refresh user profile from backend and update AuthProvider
  Future<void> refreshProfile(AuthProvider authProvider) async {
    if (!_connected) return;

    try {
      final profileData = await _bridge.getProfile();
      final userData = profileData['user'] as Map<String, dynamic>?;
      if (userData != null) {
        await authProvider.updateFromBackend(
          id: (userData['id'] ?? '').toString(),
          name: userData['displayName']?.toString() ??
              userData['name']?.toString() ??
              'User',
          email: userData['email']?.toString() ?? '',
          role: userData['roleDisplay']?.toString().toLowerCase() ??
              userData['role']?.toString().toLowerCase() ??
              'user',
        );
      }
    } catch (e) {
      debugPrint('Failed to refresh profile: $e');
      rethrow;
    }
  }

  /// Get monthly sales target from backend
  Future<Map<String, dynamic>> getMonthlyTarget({int? year, int? month}) async {
    if (!_connected) {
      throw Exception('Not connected to warehouse backend');
    }
    try {
      return await _bridge.getMonthlyTarget(year: year, month: month);
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        await disconnect();
      }
      rethrow;
    }
  }

  /// Set monthly sales target in backend
  Future<Map<String, dynamic>> setMonthlyTarget({
    required int year,
    required int month,
    required double monthlyTarget,
  }) async {
    if (!_connected) {
      throw Exception('Not connected to warehouse backend');
    }
    try {
      return await _bridge.setMonthlyTarget(
        year: year,
        month: month,
        monthlyTarget: monthlyTarget,
      );
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        await disconnect();
      }
      rethrow;
    }
  }

  /// Get products for sale (with stock and pricing info)
  Future<List<Product>> getProductsForSale({
    bool hasStock = true,
    bool hasPrice = true,
  }) async {
    if (!_connected) {
      // Return local products if not connected
      return _products.where((product) {
        if (!isProductActive(product)) return false;
        if (hasPrice && product.price <= 0) return false;
        if (hasStock && (product.stockQuantity ?? 0) <= 0) return false;
        return true;
      }).toList();
    }
    try {
      return await _bridge.getProductsForSale(
        hasStock: hasStock,
        hasPrice: hasPrice,
      );
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        await disconnect();
      }
      // Fallback to local products
      return _products.where((product) {
        if (!isProductActive(product)) return false;
        if (hasPrice && product.price <= 0) return false;
        if (hasStock && (product.stockQuantity ?? 0) <= 0) return false;
        return true;
      }).toList();
    }
  }
}
