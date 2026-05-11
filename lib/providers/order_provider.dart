import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/order_model.dart';
import '../models/sales_item_model.dart';
import '../utils/order_schedule_utils.dart';

class OrderProvider extends ChangeNotifier {
  List<Order> _orders = [];
  bool _isLoading = false;
  String? _error;

  List<Order> get orders => _orders;
  bool get isLoading => _isLoading;
  String? get error => _error;

  int? _retryAfterSeconds(DioException e) {
    final v = e.response?.headers.value('retry-after');
    if (v == null) return null;
    return int.tryParse(v.trim());
  }

  String _userFriendlyFetchError(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode;
      if (code == 429) {
        final ra = _retryAfterSeconds(e);
        if (ra != null && ra > 0) {
          return 'Хэт олон хүсэлт илгээсэн (429). $ra секундын дараа дахин оролдоно уу.';
        }
        return 'Хэт олон хүсэлт илгээсэн. Түр хүлээгээд «Дахин оролдох» дарна уу.';
      }
      final data = e.response?.data;
      if (data is Map && data['message'] != null) {
        return data['message'].toString();
      }
      if (code != null) {
        return 'Захиалга татахад алдаа гарлаа (код $code).';
      }
    }
    return e.toString().split('\n').first;
  }

  /// Backend (warehouse-service) нь заримдаа `orderItems.freeQuantity` / `paidQuantity`
  /// талбаруудыг буцаадаггүй.
  ///
  /// Тийм үед mobile талын сагсны (SalesItem) мэдээллээр тухайн захиалгын мөрүүдийн
  /// `freeQuantity`-г UI дээр харагдахаар нөхөж өгнө.
  ///
  /// Анхааруулга: Энэ нь зөвхөн mobile UI/локал model-д нөлөөлнө; backend-д юу ч засахгүй.
  void patchOrderFreeQuantitiesFromCart({
    required String orderId,
    required List<SalesItem> cart,
  }) {
    if (_orders.isEmpty) return;

    final byProductId = <String, SalesItem>{};
    for (final it in cart) {
      byProductId[it.productId] = it;
    }

    var changed = false;
    final next = _orders.map((o) {
      if (o.id != orderId) return o;

      final patchedItems = o.items.map((line) {
        final cartLine = byProductId[line.productId];
        if (cartLine == null) return line;

        final fq = cartLine.freeQuantity < 0 ? 0 : cartLine.freeQuantity;
        if (fq <= 0) return line;

        final paidPieces = (cartLine.quantity - fq);
        final paid = paidPieces < 0 ? 0 : paidPieces;
        final quantityTotal = paid + fq;

        changed = true;
        return OrderItem(
          productId: line.productId,
          productName: line.productName,
          quantity: quantityTotal,
          unitPrice: line.unitPrice,
          totalPrice: line.unitPrice * paid,
          unitsPerBox: line.unitsPerBox,
          orderedUnit: line.orderedUnit,
          orderedQuantity: line.orderedQuantity,
          freeQuantity: fq,
        );
      }).toList();

      return Order(
        id: o.id,
        customerName: o.customerName,
        customerPhone: o.customerPhone,
        customerAddress: o.customerAddress,
        items: patchedItems,
        totalAmount: o.totalAmount,
        status: o.status,
        orderDate: o.orderDate,
        deliveryDate: o.deliveryDate,
        notes: o.notes,
        salespersonId: o.salespersonId,
        salespersonName: o.salespersonName,
        ebarimtRegistered: o.ebarimtRegistered,
        ebarimtBillId: o.ebarimtBillId,
        ebarimtReturnId: o.ebarimtReturnId,
        ebarimtLottery: o.ebarimtLottery,
        ebarimtQrData: o.ebarimtQrData,
        ebarimtStatus: o.ebarimtStatus,
      );
    }).toList();

    if (!changed) return;
    _orders = next;
    notifyListeners();
  }

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

      const maxAttempts = 4;
      Response<Map<String, dynamic>>? response;
      for (var attempt = 1; attempt <= maxAttempts; attempt++) {
        try {
          response = await dio.get<Map<String, dynamic>>(
            'orders',
            queryParameters: params,
          );
          break;
        } on DioException catch (e) {
          final status = e.response?.statusCode;
          if (status == 429 && attempt < maxAttempts) {
            final ra = _retryAfterSeconds(e);
            final backoff = ra ?? (attempt * 2);
            if (kDebugMode) {
              debugPrint(
                  '[OrderProvider] ⏳ 429 Too Many Requests, waiting ${backoff}s (attempt $attempt/$maxAttempts)');
            }
            await Future<void>.delayed(Duration(seconds: backoff));
            continue;
          }
          rethrow;
        }
      }

      if (response == null) {
        throw Exception('Захиалга татаж чадсангүй.');
      }

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
          final qtyWire = (itemMap['quantity'] as num?)?.toInt() ?? 0;
          final paidWireRaw = (itemMap['paidQuantity'] as num?)?.toInt();
          final upbRaw = (itemMap['unitsPerBox'] as num?)?.toInt() ??
              (product?['unitsPerBox'] as num?)?.toInt() ??
              1;
          final upb = upbRaw <= 0 ? 1 : upbRaw;
          final freeQRaw = (itemMap['freeQuantity'] as num?)?.toInt() ?? 0;
          var cappedFree = freeQRaw < 0 ? 0 : freeQRaw;
          late final int paidPieces;
          late final int quantityTotalPieces;
          if (paidWireRaw != null) {
            // Шинэ: `quantity` = зөвхөн төлөх; нийт физик = paidQuantity + freeQuantity.
            paidPieces = paidWireRaw < 0 ? 0 : paidWireRaw;
            quantityTotalPieces = paidPieces + cappedFree;
          } else {
            // Хуучин: `quantity` = нийт (төлөх+үнэгүй).
            if (cappedFree > qtyWire) cappedFree = qtyWire;
            paidPieces = qtyWire - cappedFree;
            quantityTotalPieces = qtyWire;
          }
          int? orderedQty = (itemMap['orderedQuantity'] as num?)?.toInt();
          final ouRaw =
              (itemMap['orderedUnit']?.toString() ?? 'piece').trim();
          final ou = ouRaw.isEmpty ? 'piece' : ouRaw;
          if (orderedQty == null && ou == 'box' && upb > 1) {
            orderedQty = quantityTotalPieces ~/ upb;
          }

          return OrderItem(
            productId: (itemMap['productId'] ?? '').toString(),
            productName:
                product?['nameMongolian']?.toString() ?? 'Unknown Product',
            quantity: quantityTotalPieces,
            unitPrice: unitPrice,
            totalPrice: unitPrice * (paidPieces < 0 ? 0 : paidPieces),
            unitsPerBox: upb,
            orderedUnit: ou,
            orderedQuantity: orderedQty,
            freeQuantity: cappedFree,
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
      _error = _userFriendlyFetchError(e);
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

  /// [role]: [OrderScheduleUtils.effectiveOrderCalendarDay]-тай ижил дүрмээр өдөр тогтооно.
  List<Order> getOrdersByDateRange(
    DateTime startDate,
    DateTime endDate, {
    String role = '',
  }) {
    return _orders.where((order) {
      final effective =
          OrderScheduleUtils.effectiveOrderCalendarDay(order, role: role);
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
