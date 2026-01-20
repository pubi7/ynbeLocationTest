import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

import '../models/product_model.dart';
import '../models/shop_model.dart';
import '../services/warehouse_web_bridge.dart';

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
      {required String identifier, required String password}) async {
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final token =
          await _bridge.login(identifier: identifier, password: password);
      _token = token;

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

  Future<void> refreshShops({int pageSize = 200}) async {
    if (!_connected) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
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
}
