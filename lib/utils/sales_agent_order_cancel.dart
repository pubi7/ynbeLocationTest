import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/order_model.dart';
import '../providers/auth_provider.dart';
import '../providers/order_provider.dart';
import '../providers/product_provider.dart';
import '../providers/warehouse_provider.dart';
import 'ebarimt_order_return.dart';

/// `order_details_screen` болон энд ижил түлхүүр ашиглана (гар утсанд eBarimt хэвлэсэн ID-нууд).
const String kPrintedEbarimtOrderIdsPrefKey = 'printed_ebarimt_orders_v1';

/// Серверийн баримт эсвэл гар утсанд хэвлэгдсэн гэж prefs-д тэмдэглэгдсэн эсэх.
bool orderReceiptPrintedForAgentCancel(
  Order order,
  Set<String> locallyPrintedOrderIds,
) {
  if (order.ebarimtRegistered) return true;
  if ((order.ebarimtBillId ?? '').trim().isNotEmpty) return true;
  if ((order.ebarimtLottery ?? '').trim().isNotEmpty) return true;
  if ((order.ebarimtQrData ?? '').trim().isNotEmpty) return true;
  return locallyPrintedOrderIds.contains(order.id.trim());
}

Future<Set<String>> readLocallyPrintedOrderIds() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kPrintedEbarimtOrderIdsPrefKey);
    if (raw == null || raw.trim().isEmpty) return <String>{};
    final decoded = jsonDecode(raw);
    if (decoded is! List) return <String>{};
    return decoded.map((e) => e.toString()).where((s) => s.isNotEmpty).toSet();
  } catch (_) {
    return <String>{};
  }
}

/// Төлөөлөгчийн өөрийн, хүлээгдэж буй захиалгыг цуцлах (баримт буцаах урсгалтай давхцуулахгүй).
bool orderCanSalesAgentCancelOwnPending(
  Order order, {
  required String? currentUserId,
  Set<String> locallyPrintedOrderIds = const {},
}) {
  final myId = (currentUserId ?? '').trim();
  if (myId.isEmpty) return false;
  if (order.salespersonId.trim() != myId) return false;
  final s = order.status.toLowerCase();
  if (s == 'cancelled') return false;
  if (s == 'delivered') return false;
  if (orderReceiptPrintedForAgentCancel(order, locallyPrintedOrderIds)) {
    return false;
  }
  if (orderCanReturnEbarimtReceipt(order)) return false;
  return s == 'pending' || s == 'confirmed';
}

String _errorMessage(Object e) {
  if (e is DioException) {
    final d = e.response?.data;
    if (d is Map && d['message'] != null) {
      return d['message'].toString();
    }
    return e.message ?? e.toString();
  }
  return e.toString();
}

Future<void> _refreshLocalProducts(BuildContext context) async {
  final warehouse = Provider.of<WarehouseProvider>(context, listen: false);
  if (!warehouse.connected) return;
  try {
    await warehouse.refreshProducts();
    if (!context.mounted) return;
    final products = Provider.of<ProductProvider>(context, listen: false);
    products.setProducts(warehouse.products);
  } catch (_) {}
}

/// Сервер дээр статус `Cancelled` болгож, жагсаалт + барааны үлдэгдлийг шинэчилнэ.
Future<bool> confirmSalesAgentCancelPendingOrder(
  BuildContext context,
  Order order,
) async {
  final auth = Provider.of<AuthProvider>(context, listen: false);
  final localPrinted = await readLocallyPrintedOrderIds();
  if (orderReceiptPrintedForAgentCancel(order, localPrinted)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Баримт хэвлэгдсэн тул захиалга цуцлах боломжгүй.'),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return false;
  }
  if (!orderCanSalesAgentCancelOwnPending(
    order,
    currentUserId: auth.user?.id,
    locallyPrintedOrderIds: localPrinted,
  )) {
    return false;
  }

  final oid = int.tryParse(order.id);
  if (oid == null) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Захиалгын ID буруу байна')),
      );
    }
    return false;
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Захиалга цуцлах'),
      content: Text(
        'Энэ захиалгыг цуцлах уу? Дэлгүүр: ${order.customerName}\n\n'
        'Сервер дээр статус «Cancelled» болж, барааны үлдэгдэл сэргээгдэнэ (холбогдсон API-аас хамаарна).',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Болих'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
          child: const Text('Цуцлах'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;

  final warehouse = Provider.of<WarehouseProvider>(context, listen: false);
  final orders = Provider.of<OrderProvider>(context, listen: false);

  if (!warehouse.connected) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Серверт холбогдоогүй байна')),
    );
    return false;
  }

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );

  try {
    await warehouse.updateOrderStatus(orderId: oid, status: 'Cancelled');
    await orders.fetchOrders(warehouse.dio);
    await _refreshLocalProducts(context);
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Захиалга цуцлагдлаа'),
          backgroundColor: Colors.green,
        ),
      );
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(e))),
      );
    }
    return false;
  }
}
