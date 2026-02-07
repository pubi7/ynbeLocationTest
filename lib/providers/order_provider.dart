import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../models/order_model.dart';

class OrderProvider extends ChangeNotifier {
  List<Order> _orders = [];
  bool _isLoading = false;
  String? _error;

  List<Order> get orders => _orders;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Fetch orders from backend API using the authenticated Dio instance
  /// [dio] - Dio instance from WarehouseWebBridge (already has auth token set)
  Future<void> fetchOrders(Dio dio) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await dio.get<Map<String, dynamic>>(
        'orders',
        queryParameters: {'limit': 'all'},
      );

      final data = response.data;
      if (data == null) {
        _orders = [];
        _isLoading = false;
        notifyListeners();
        return;
      }

      final innerData = data['data'] as Map<String, dynamic>?;
      final rawOrders = (innerData?['orders'] as List?) ?? [];

      _orders = rawOrders.map((o) {
        final orderMap = o as Map<String, dynamic>;

        // Parse order items from backend format
        final rawItems = (orderMap['orderItems'] as List?) ?? [];
        final items = rawItems.map((item) {
          final itemMap = item as Map<String, dynamic>;
          final product = itemMap['product'] as Map<String, dynamic>?;
          final unitPrice =
              double.tryParse(itemMap['unitPrice']?.toString() ?? '0') ?? 0.0;
          final qty = (itemMap['quantity'] as num?)?.toInt() ?? 0;

          return OrderItem(
            productId: (itemMap['productId'] ?? '').toString(),
            productName:
                product?['nameMongolian']?.toString() ?? 'Unknown Product',
            quantity: qty,
            unitPrice: unitPrice,
            totalPrice: unitPrice * qty,
          );
        }).toList();

        // Parse customer info
        final customer = orderMap['customer'] as Map<String, dynamic>?;
        final agent = orderMap['agent'] ?? orderMap['createdBy'];
        final agentMap = agent is Map<String, dynamic> ? agent : null;

        return Order(
          id: (orderMap['id'] ?? '').toString(),
          customerName: customer?['name']?.toString() ?? 'Unknown',
          customerPhone: customer?['phoneNumber']?.toString() ?? '',
          customerAddress: customer?['address']?.toString() ?? '',
          items: items,
          totalAmount:
              double.tryParse(orderMap['totalAmount']?.toString() ?? '0') ??
                  0.0,
          status: _mapBackendStatus(orderMap['status']?.toString() ?? ''),
          orderDate: DateTime.tryParse(
                  orderMap['orderDate']?.toString() ??
                      orderMap['createdAt']?.toString() ??
                      '') ??
              DateTime.now(),
          notes: orderMap['notes']?.toString(),
          salespersonId: (agentMap?['id'] ?? '').toString(),
          salespersonName: agentMap?['name']?.toString() ?? '',
        );
      }).toList();

      if (kDebugMode) {
        debugPrint(
            '[OrderProvider] ✅ Backend-аас ${_orders.length} захиалга татлаа');
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OrderProvider] ❌ Захиалга татахад алдаа: $e');
      }
      _error = 'Захиалга татахад алдаа гарлаа: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Map backend status to local status format
  String _mapBackendStatus(String backendStatus) {
    switch (backendStatus) {
      case 'Pending':
        return 'pending';
      case 'Fulfilled':
        return 'confirmed';
      case 'Cancelled':
        return 'cancelled';
      default:
        return backendStatus.toLowerCase();
    }
  }

  Future<void> addOrder(Order order) async {
    _orders.insert(0, order);
    notifyListeners();
  }

  Future<void> updateOrder(Order order) async {
    final index = _orders.indexWhere((o) => o.id == order.id);
    if (index != -1) {
      _orders[index] = order;
      notifyListeners();
    }
  }

  Future<void> deleteOrder(String orderId) async {
    _orders.removeWhere((order) => order.id == orderId);
    notifyListeners();
  }

  List<Order> getOrdersByStatus(String status) {
    return _orders.where((order) => order.status == status).toList();
  }

  Order? getOrderById(String id) {
    final idx = _orders.indexWhere((o) => o.id == id);
    if (idx == -1) return null;
    return _orders[idx];
  }

  List<Order> getOrdersByDateRange(DateTime startDate, DateTime endDate) {
    return _orders.where((order) {
      return order.orderDate.isAfter(startDate) &&
          order.orderDate.isBefore(endDate);
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
