import 'package:flutter/material.dart';
import '../models/shop_model.dart';
import '../models/sales_model.dart';

class ShopProvider extends ChangeNotifier {
  List<Shop> _shops = [];
  bool _isLoading = false;
  String? _error;

  List<Shop> get shops => _shops;
  bool get isLoading => _isLoading;
  String? get error => _error;

  ShopProvider() {
    _loadMockData();
  }

  void _loadMockData() {
    _shops = [
      Shop(
        id: '1',
        name: 'Дэлгүүр 1 - Сүхбаатар дүүрэг',
        address: 'Сүхбаатар дүүрэг, 1-р хороо',
        latitude: 47.9200,
        longitude: 106.9200,
        phone: '99112233',
        status: 'active',
        orders: [],
        sales: [],
        lastVisit: DateTime.now().subtract(const Duration(days: 1)),
      ),
      Shop(
        id: '2',
        name: 'Дэлгүүр 2 - Баянзүрх дүүрэг',
        address: 'Баянзүрх дүүрэг, 2-р хороо',
        latitude: 47.9150,
        longitude: 106.9150,
        phone: '99223344',
        status: 'active',
        orders: [],
        sales: [],
        lastVisit: DateTime.now().subtract(const Duration(days: 2)),
      ),
      Shop(
        id: '3',
        name: 'Дэлгүүр 3 - Хан-Уул дүүрэг',
        address: 'Хан-Уул дүүрэг, 3-р хороо',
        latitude: 47.9250,
        longitude: 106.9250,
        phone: '99334455',
        status: 'active',
        orders: [],
        sales: [],
        lastVisit: DateTime.now().subtract(const Duration(days: 3)),
      ),
      Shop(
        id: '4',
        name: 'Дэлгүүр 4 - Баянгол дүүрэг',
        address: 'Баянгол дүүрэг, 4-р хороо',
        latitude: 47.9300,
        longitude: 106.9300,
        phone: '99445566',
        status: 'active',
        orders: [],
        sales: [],
        lastVisit: DateTime.now().subtract(const Duration(days: 5)),
      ),
    ];
    notifyListeners();
  }

  Shop? getShopById(String id) {
    try {
      return _shops.firstWhere((shop) => shop.id == id);
    } catch (e) {
      return null;
    }
  }

  Shop? getShopByName(String name) {
    try {
      return _shops.firstWhere((shop) => shop.name == name);
    } catch (e) {
      return null;
    }
  }

  // Зээлээр авсан төлбөр хийгээгүй дэлгүүрүүдийг шалгах
  bool hasUnpaidCredit(String shopName, List<Sales> allSales) {
    // Зээлээр авсан sales-уудыг олох
    final creditSales = allSales.where((sale) {
      return sale.location == shopName && 
             sale.paymentMethod != null && 
             sale.paymentMethod!.toLowerCase() == 'зээл';
    }).toList();
    
    // Төлбөр хийгээгүй зээл байгаа эсэхийг шалгах
    // Одоогоор зээлээр авсан sales байвал төлбөр хийгээгүй гэж үзнэ
    return creditSales.isNotEmpty;
  }

  // Дэлгүүрийн зээлээр авсан нийт дүнг тооцоолох
  double getUnpaidCreditAmount(String shopName, List<Sales> allSales) {
    final creditSales = allSales.where((sale) {
      return sale.location == shopName && 
             sale.paymentMethod != null && 
             sale.paymentMethod!.toLowerCase() == 'зээл';
    }).toList();
    
    return creditSales.fold(0.0, (sum, sale) => sum + sale.amount);
  }

  void addShop(Shop shop) {
    _shops.add(shop);
    notifyListeners();
  }

  void updateShop(Shop shop) {
    final index = _shops.indexWhere((s) => s.id == shop.id);
    if (index != -1) {
      _shops[index] = shop;
      notifyListeners();
    }
  }

  void deleteShop(String id) {
    _shops.removeWhere((shop) => shop.id == id);
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}

