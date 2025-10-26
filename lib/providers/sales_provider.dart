import 'package:flutter/material.dart';
import '../models/sales_model.dart';

class SalesProvider extends ChangeNotifier {
  List<Sales> _sales = [];
  bool _isLoading = false;
  String? _error;

  List<Sales> get sales => _sales;
  bool get isLoading => _isLoading;
  String? get error => _error;

  SalesProvider() {
    _loadMockData();
  }

  void _loadMockData() {
    _sales = [
      Sales(
        id: '1',
        productName: 'Product A',
        location: 'Shop 1, Downtown',
        salespersonId: '2',
        salespersonName: 'Sales Staff',
        amount: 150.0,
        saleDate: DateTime.now().subtract(const Duration(days: 1)),
        notes: 'Good customer response',
      ),
      Sales(
        id: '2',
        productName: 'Product B',
        location: 'Shop 2, Mall',
        salespersonId: '2',
        salespersonName: 'Sales Staff',
        amount: 200.0,
        saleDate: DateTime.now().subtract(const Duration(days: 2)),
        notes: 'Bulk order',
      ),
    ];
  }

  Future<void> addSale(Sales sale) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));
      
      _sales.insert(0, sale);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Error adding sale: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateSale(Sales sale) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));
      
      final index = _sales.indexWhere((s) => s.id == sale.id);
      if (index != -1) {
        _sales[index] = sale;
      }
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Error updating sale: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteSale(String saleId) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));
      
      _sales.removeWhere((sale) => sale.id == saleId);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Error deleting sale: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  List<Sales> getSalesByDateRange(DateTime startDate, DateTime endDate) {
    return _sales.where((sale) {
      return sale.saleDate.isAfter(startDate) && sale.saleDate.isBefore(endDate);
    }).toList();
  }

  List<Sales> getSalesByLocation(String location) {
    return _sales.where((sale) => sale.location.toLowerCase().contains(location.toLowerCase())).toList();
  }

  double getTotalSales() {
    return _sales.fold(0.0, (sum, sale) => sum + sale.amount);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
