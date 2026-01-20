import 'package:flutter/material.dart';
import '../models/product_model.dart';

class ProductProvider extends ChangeNotifier {
  List<Product> _products = [];
  bool _isUsingMock = true;

  List<Product> get products => _products;
  bool get isUsingMock => _isUsingMock;

  ProductProvider() {
    // Start empty (no demo/mock products)
    _products = [];
    _isUsingMock = false;
  }

  void _loadMockData() {
    // Deprecated: kept only for backward compatibility with older screens.
    // Intentionally leave empty so demo products do not appear.
    _products = [];
    _isUsingMock = false;
    notifyListeners();
  }

  void setProducts(List<Product> products) {
    _products = products;
    _isUsingMock = false;
    notifyListeners();
  }

  void resetToMock() {
    _loadMockData();
  }

  Product? getProductById(String id) {
    try {
      return _products.firstWhere((product) => product.id == id);
    } catch (e) {
      return null;
    }
  }

  void addProduct(Product product) {
    _products.add(product);
    notifyListeners();
  }

  void updateProduct(Product product) {
    final index = _products.indexWhere((p) => p.id == product.id);
    if (index != -1) {
      _products[index] = product;
      notifyListeners();
    }
  }

  void deleteProduct(String id) {
    _products.removeWhere((product) => product.id == id);
    notifyListeners();
  }
}

