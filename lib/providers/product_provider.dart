import 'package:flutter/material.dart';
import '../models/product_model.dart';

class ProductProvider extends ChangeNotifier {
  List<Product> _products = [];

  List<Product> get products => _products;

  ProductProvider() {
    _loadMockData();
  }

  void _loadMockData() {
    _products = [
      Product(
        id: '1',
        name: 'Бүтээгдэхүүн A',
        price: 50000.0,
        description: 'Тайлбар A',
        category: 'Ангилал 1',
      ),
      Product(
        id: '2',
        name: 'Бүтээгдэхүүн B',
        price: 75000.0,
        description: 'Тайлбар B',
        category: 'Ангилал 1',
      ),
      Product(
        id: '3',
        name: 'Бүтээгдэхүүн C',
        price: 100000.0,
        description: 'Тайлбар C',
        category: 'Ангилал 2',
      ),
      Product(
        id: '4',
        name: 'Бүтээгдэхүүн D',
        price: 125000.0,
        description: 'Тайлбар D',
        category: 'Ангилал 2',
      ),
      Product(
        id: '5',
        name: 'Бүтээгдэхүүн E',
        price: 150000.0,
        description: 'Тайлбар E',
        category: 'Ангилал 3',
      ),
    ];
    notifyListeners();
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

