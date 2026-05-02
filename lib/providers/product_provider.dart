import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../utils/product_active_utils.dart';

class ProductProvider extends ChangeNotifier {
  List<Product> _products = [];

  List<Product> get products => _products;

  ProductProvider() {
    // Start empty (no demo/mock products)
    _products = [];
  }

  void setProducts(List<Product> products) {
    // Зөвхөн идэвхтэй барааг хадгална (идэвхгүйг апп даяар нууна).
    _products = products.where(isProductActive).toList();
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

  /// Захиалга цуцлахад API үлдэгдэл шууд сэргээхгүй үед: мөр бүрийн [quantity] (нийт ширхэг)-ийг нөөцөд нэмнө.
  void bumpStockByProductId(Map<String, int> addPiecesByProductId) {
    if (addPiecesByProductId.isEmpty) return;
    _products = _products.map((p) {
      final add = addPiecesByProductId[p.id];
      if (add == null || add == 0) return p;
      final cur = p.stockQuantity ?? 0;
      return p.withStockQuantity(cur + add);
    }).toList();
    notifyListeners();
  }
}
