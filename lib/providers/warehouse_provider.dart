import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/product_model.dart';
import '../models/shop_model.dart';
import '../services/warehouse_web_bridge.dart';
import 'auth_provider.dart';

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
    await _bridge.setApiBaseUrl(input);
    await _bridge.saveApiBaseUrl(input);
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
      // Add small delay to prevent rapid-fire requests
      await Future.delayed(const Duration(milliseconds: 300));

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
  Future<bool> connectWithExistingToken({AuthProvider? authProvider}) async {
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

      // Fetch user profile and update AuthProvider
      if (authProvider != null) {
        await _fetchAndUpdateProfile(authProvider, '');
      }

      _connected = true;
      _loading = false;
      if (kDebugMode) {
        debugPrint('[WarehouseProvider] ✅ Connected with existing token (no double login)');
      }
      notifyListeners();
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[WarehouseProvider] ❌ connectWithExistingToken failed: $e');
      }
      _error = e.toString();
      _connected = false;
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  /// Helper to fetch user profile and update AuthProvider
  Future<void> _fetchAndUpdateProfile(AuthProvider authProvider, String fallbackEmail) async {
    try {
      await Future.delayed(const Duration(milliseconds: 200));
      final profileData = await _bridge.getProfile();
      final userData = profileData['user'] as Map<String, dynamic>?;
      if (userData != null) {
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
            if (kDebugMode) {
              debugPrint(
                  '[WarehouseProvider] ✅ Agent ID хадгалагдлаа: $agentIdInt');
            }
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

  Future<void> refreshProducts() async {
    if (!_connected) {
      if (kDebugMode)
        debugPrint(
            '[WarehouseProvider] ⚠️ Not connected, skipping product refresh');
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      if (kDebugMode) {
        debugPrint('[WarehouseProvider] 🚀 Starting product refresh...');
      }
      _products = await _bridge.fetchAllProducts();
      if (kDebugMode) {
        debugPrint(
            '[WarehouseProvider] ✅ Successfully fetched ${_products.length} products');
        if (_products.isNotEmpty) {
          final withPrice = _products.where((p) => p.price > 0).length;
          final withStock =
              _products.where((p) => (p.stockQuantity ?? 0) > 0).length;
          debugPrint(
              '[WarehouseProvider] 📊 Product stats: $withPrice with prices, $withStock with stock');
          debugPrint(
              '[WarehouseProvider] 📦 First product: ${_products.first.name} - Price: ${_products.first.price}');
        } else {
          debugPrint('[WarehouseProvider] ⚠️ No products fetched!');
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
              '[WarehouseProvider] ❌ Error fetching products: $errorMsg');
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

  Future<void> refreshShops(
      {int pageSize = 200, AuthProvider? authProvider}) async {
    if (!_connected) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // Add delay to prevent rate limiting
      await Future.delayed(const Duration(milliseconds: 300));

      // Зөвхөн /api/customers endpoint ашиглана.
      // Backend нь SalesAgent-д зөвхөн assignedAgentId-аар filter хийсэн
      // customers-ийг л буцаана. Store table-ийн seed data (Central Wholesale
      // Market гэх мэт) орохгүй.
      _shops = await _bridge.fetchAllShops(pageSize: pageSize);

      if (kDebugMode) {
        debugPrint(
            '[WarehouseProvider] ✅ Fetched ${_shops.length} shops (assigned customers only)');
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
          debugPrint('[WarehouseProvider] ❌ Error fetching shops: $errorMsg');
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
    String? deliveryDate,
    int? creditTermDays,
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
        deliveryDate: deliveryDate,
        creditTermDays: creditTermDays,
      );
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
        if (hasPrice && product.price <= 0) return false;
        if (hasStock && (product.stockQuantity ?? 0) <= 0) return false;
        return true;
      }).toList();
    }
  }
}
