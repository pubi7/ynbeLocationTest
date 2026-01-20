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
      // Inclusive start, exclusive end
      return !sale.saleDate.isBefore(startDate) && sale.saleDate.isBefore(endDate);
    }).toList();
  }

  List<Sales> getSalesByLocation(String location) {
    return _sales.where((sale) => sale.location.toLowerCase().contains(location.toLowerCase())).toList();
  }

  double getTotalSales() {
    return _sales.fold(0.0, (sum, sale) => sum + sale.amount);
  }

  double getTotalSalesForRange(DateTime startInclusive, DateTime endExclusive) {
    return _sales
        .where((s) => !s.saleDate.isBefore(startInclusive) && s.saleDate.isBefore(endExclusive))
        .fold(0.0, (sum, s) => sum + s.amount);
  }

  double getTotalSalesForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    return getTotalSalesForRange(start, end);
  }

  double getTotalSalesForWeek(DateTime dayInWeek, {int weekStartsOn = DateTime.monday}) {
    // weekStartsOn should be DateTime.monday..DateTime.sunday
    final day = DateTime(dayInWeek.year, dayInWeek.month, dayInWeek.day);
    final diff = (day.weekday - weekStartsOn) % 7;
    final start = day.subtract(Duration(days: diff));
    final end = start.add(const Duration(days: 7));
    return getTotalSalesForRange(start, end);
  }

  double getTotalSalesForMonth(DateTime dayInMonth) {
    final start = DateTime(dayInMonth.year, dayInMonth.month, 1);
    final end = DateTime(dayInMonth.year, dayInMonth.month + 1, 1);
    return getTotalSalesForRange(start, end);
  }

  /// Returns totals grouped by hour (0..23) for the given day.
  /// Missing hours will not be present in the map (treat as 0).
  Map<int, double> getTotalSalesByHourForDay(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final Map<int, double> totals = {};
    for (final s in _sales) {
      if (s.saleDate.isBefore(start) || !s.saleDate.isBefore(end)) continue;
      final h = s.saleDate.hour;
      totals[h] = (totals[h] ?? 0) + s.amount;
    }
    return totals;
  }

  /// Returns totals grouped by day (DateTime at midnight) for the range.
  /// Missing days will not be present in the map (treat as 0).
  Map<DateTime, double> getTotalSalesByDayForRange(DateTime startInclusive, DateTime endExclusive) {
    final Map<DateTime, double> totals = {};
    for (final s in _sales) {
      if (s.saleDate.isBefore(startInclusive) || !s.saleDate.isBefore(endExclusive)) continue;
      final d = DateTime(s.saleDate.year, s.saleDate.month, s.saleDate.day);
      totals[d] = (totals[d] ?? 0) + s.amount;
    }
    return totals;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
