import 'package:dio/dio.dart';
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
  /// [startDate] - optional: filter orders from this date (inclusive)
  /// [endDate] - optional: filter orders until this date (inclusive)
  Future<void> fetchOrders(Dio dio,
      {DateTime? startDate, DateTime? endDate}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final params = <String, String>{'limit': 'all'};
      String _toDateStr(DateTime d) =>
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      if (startDate != null) {
        params['startDate'] = _toDateStr(
            DateTime(startDate.year, startDate.month, startDate.day));
      }
      if (endDate != null) {
        // Backend uses lte; pass next day so we get full selected day
        final nextDay = DateTime(endDate.year, endDate.month, endDate.day)
            .add(const Duration(days: 1));
        params['endDate'] = _toDateStr(nextDay);
      }

      final response = await dio.get<Map<String, dynamic>>(
        'orders',
        queryParameters: params,
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
          final upbRaw = (itemMap['unitsPerBox'] as num?)?.toInt() ??
              (product?['unitsPerBox'] as num?)?.toInt() ??
              1;
          final upb = upbRaw <= 0 ? 1 : upbRaw;
          final freeQ = (itemMap['freeQuantity'] as num?)?.toInt() ?? 0;
          int? orderedQty = (itemMap['orderedQuantity'] as num?)?.toInt();
          final ouRaw =
              (itemMap['orderedUnit']?.toString() ?? 'piece').trim();
          final ou = ouRaw.isEmpty ? 'piece' : ouRaw;
          if (orderedQty == null && ou == 'box' && upb > 1) {
            orderedQty = qty ~/ upb;
          }

          return OrderItem(
            productId: (itemMap['productId'] ?? '').toString(),
            productName:
                product?['nameMongolian']?.toString() ?? 'Unknown Product',
            quantity: qty,
            unitPrice: unitPrice,
            totalPrice: unitPrice * qty,
            unitsPerBox: upb,
            orderedUnit: ou,
            orderedQuantity: orderedQty,
            freeQuantity: freeQ < 0 ? 0 : (freeQ > qty ? qty : freeQ),
          );
        }).toList();

        DateTime _parseBackendDate(dynamic v) {
          final s = (v ?? '').toString().trim();
          if (s.isEmpty) return DateTime.now();

          // If backend includes timezone info (Z or ±HH:MM), parse then convert to local.
          // If no timezone info, treat as already-local.
          final hasTz = RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(s);
          final dt = DateTime.tryParse(s);
          if (dt == null) return DateTime.now();
          return hasTz ? dt.toLocal() : dt;
        }

        DateTime? _parseBackendDay(dynamic v) {
          final s = (v ?? '').toString().trim();
          if (s.isEmpty) return null;
          // Usually YYYY-MM-DD from backend
          final dt = DateTime.tryParse(s);
          if (dt == null) return null;
          return DateTime(dt.year, dt.month, dt.day);
        }

        // Parse customer info
        final customer = orderMap['customer'] as Map<String, dynamic>?;
        final agent = orderMap['agent'] ?? orderMap['createdBy'];
        final agentMap = agent is Map<String, dynamic> ? agent : null;
        final agentIdFallback = (orderMap['agentId'] ??
                orderMap['createdById'] ??
                orderMap['userId'] ??
                '')
            .toString();
        final agentNameFallback =
            (orderMap['agentName'] ?? orderMap['createdByName'] ?? '')
                .toString();

        final ebarimtRegistered = orderMap['ebarimtRegistered'] == true;
        final backendStatus = orderMap['status']?.toString() ?? '';
        // UI дээр:
        // - Захиалга үүссэн ч баримт/хүргэлт хийгдээгүй бол pending
        // - Баримт гарсан (ebarimtRegistered) эсвэл backend Fulfilled бол fulfilled/delivered гэж үзнэ
        final localStatus = (ebarimtRegistered || backendStatus == 'Fulfilled')
            ? 'delivered'
            : _mapBackendStatus(backendStatus);

        final deliveryDateRaw = orderMap['deliveryDate'] ??
            orderMap['delivery_date'] ??
            orderMap['deliveryDay'] ??
            orderMap['delivery_day'];

        return Order(
          id: (orderMap['id'] ?? '').toString(),
          customerName: customer?['name']?.toString() ?? 'Unknown',
          customerPhone: customer?['phoneNumber']?.toString() ?? '',
          customerAddress: customer?['address']?.toString() ?? '',
          items: items,
          totalAmount:
              double.tryParse(orderMap['totalAmount']?.toString() ?? '0') ??
                  0.0,
          status: localStatus,
          orderDate: _parseBackendDate(
            orderMap['orderDate'] ?? orderMap['createdAt'],
          ),
          deliveryDate: _parseBackendDay(deliveryDateRaw),
          notes: orderMap['notes']?.toString(),
          salespersonId: ((agentMap?['id'] ?? '').toString().trim().isNotEmpty
                  ? (agentMap?['id'] ?? '').toString()
                  : agentIdFallback)
              .toString(),
          salespersonName: (agentMap?['name']?.toString() ?? '').trim().isNotEmpty
              ? agentMap!['name']!.toString()
              : agentNameFallback,
          ebarimtRegistered: ebarimtRegistered,
          ebarimtBillId: orderMap['ebarimtBillId']?.toString() ??
              orderMap['billId']?.toString(),
          ebarimtReturnId: orderMap['ebarimtReturnId']?.toString(),
          ebarimtLottery: orderMap['ebarimtLottery']?.toString() ??
              orderMap['lottery']?.toString(),
          ebarimtQrData: orderMap['ebarimtQrData']?.toString() ??
              orderMap['qrData']?.toString(),
          ebarimtStatus: orderMap['ebarimtStatus']?.toString(),
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
        return 'delivered';
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
      // Prefer scheduled delivery day when available.
      // Use inclusive range: start <= date <= end.
      final effective = order.deliveryDate ?? order.orderDate;
      return !effective.isBefore(startDate) && !effective.isAfter(endDate);
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
