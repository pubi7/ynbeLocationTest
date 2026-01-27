import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

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
    await _bridge.setApiBaseUrl(input);
    await _bridge.saveApiBaseUrl(input);
    notifyListeners();
  }

  Future<bool> connect(
      {required String identifier, required String password, AuthProvider? authProvider}) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final token =
          await _bridge.login(identifier: identifier, password: password);
      _token = token;

      // Fetch user profile and update AuthProvider
      if (authProvider != null) {
        try {
          final profileData = await _bridge.getProfile();
          final userData = profileData['user'] as Map<String, dynamic>?;
          if (userData != null) {
            await authProvider.updateFromBackend(
              id: (userData['id'] ?? '').toString(),
              name: userData['displayName']?.toString() ?? userData['name']?.toString() ?? 'User',
              email: userData['email']?.toString() ?? identifier,
              role: userData['roleDisplay']?.toString().toLowerCase() ?? userData['role']?.toString().toLowerCase() ?? 'user',
            );
          }
        } catch (e) {
          // If profile fetch fails, continue with connection
          debugPrint('Failed to fetch profile: $e');
        }
      }

      _connected = true;
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _connected = false;
      _loading = false;
      notifyListeners();
      return false;
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
    if (!_connected) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _products = await _bridge.fetchAllProducts();
      _loading = false;
      notifyListeners();
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        await disconnect();
        return;
      }
      _error = e.toString();
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshShops({int pageSize = 200, AuthProvider? authProvider}) async {
    if (!_connected) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      // Try to fetch agent stores first for all users
      // fetchAgentStores already has fallback logic, so it's safe to try
      // This ensures agent-login users can see their stores even if role isn't set correctly
      try {
        final agentShops = await _bridge.fetchAgentStores();
        // Only use agent stores if we got results, otherwise fallback
        if (agentShops.isNotEmpty) {
          _shops = agentShops;
          _loading = false;
          notifyListeners();
          return;
        }
      } catch (e) {
        // If agent stores fetch fails, fallback to regular customers endpoint
        debugPrint('Failed to fetch agent stores, falling back to customers: $e');
      }
      
      // Fallback to regular customers endpoint
      _shops = await _bridge.fetchAllShops(pageSize: pageSize);
      _loading = false;
      notifyListeners();
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 401) {
        await disconnect();
        return;
      }
      _error = e.toString();
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
          name: userData['displayName']?.toString() ?? userData['name']?.toString() ?? 'User',
          email: userData['email']?.toString() ?? '',
          role: userData['roleDisplay']?.toString().toLowerCase() ?? userData['role']?.toString().toLowerCase() ?? 'user',
        );
      }
    } catch (e) {
      debugPrint('Failed to refresh profile: $e');
      rethrow;
    }
  }
}
