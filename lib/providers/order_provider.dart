import 'package:flutter/material.dart';
import '../models/order_model.dart';

class OrderProvider extends ChangeNotifier {
  List<Order> _orders = [];
  bool _isLoading = false;
  String? _error;

  List<Order> get orders => _orders;
  bool get isLoading => _isLoading;
  String? get error => _error;

  OrderProvider() {
    _loadMockData();
  }

  void _loadMockData() {
    _orders = [
      Order(
        id: '1',
        customerName: 'John Doe',
        customerPhone: '+1234567890',
        customerAddress: '123 Main St, City',
        items: [
          OrderItem(
            productId: '1',
            productName: 'Product A',
            quantity: 2,
            unitPrice: 50.0,
            totalPrice: 100.0,
          ),
        ],
        totalAmount: 100.0,
        status: 'pending',
        orderDate: DateTime.now().subtract(const Duration(hours: 2)),
        notes: 'Customer prefers morning delivery',
        salespersonId: '2',
        salespersonName: 'Sales Staff',
      ),
      Order(
        id: '2',
        customerName: 'Jane Smith',
        customerPhone: '+0987654321',
        customerAddress: '456 Oak Ave, City',
        items: [
          OrderItem(
            productId: '2',
            productName: 'Product B',
            quantity: 1,
            unitPrice: 75.0,
            totalPrice: 75.0,
          ),
        ],
        totalAmount: 75.0,
        status: 'confirmed',
        orderDate: DateTime.now().subtract(const Duration(days: 1)),
        salespersonId: '2',
        salespersonName: 'Sales Staff',
      ),
    ];
  }

  Future<void> addOrder(Order order) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));
      
      _orders.insert(0, order);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Error adding order: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateOrder(Order order) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));
      
      final index = _orders.indexWhere((o) => o.id == order.id);
      if (index != -1) {
        _orders[index] = order;
      }
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Error updating order: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteOrder(String orderId) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));
      
      _orders.removeWhere((order) => order.id == orderId);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Error deleting order: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  List<Order> getOrdersByStatus(String status) {
    return _orders.where((order) => order.status == status).toList();
  }

  List<Order> getOrdersByDateRange(DateTime startDate, DateTime endDate) {
    return _orders.where((order) {
      return order.orderDate.isAfter(startDate) && order.orderDate.isBefore(endDate);
    }).toList();
  }

  double getTotalOrderValue() {
    return _orders.fold(0.0, (sum, order) => sum + order.totalAmount);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
