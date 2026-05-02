import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/order_model.dart';
import '../providers/order_provider.dart';
import '../providers/product_provider.dart';
import '../providers/warehouse_provider.dart';

bool orderCanReturnEbarimtReceipt(Order order) {
  if (!order.ebarimtRegistered) return false;
  final bill = order.ebarimtBillId?.trim() ?? '';
  if (bill.isEmpty) return false;
  final ret = order.ebarimtReturnId?.trim() ?? '';
  if (ret.isNotEmpty) return false;
  if (order.status.toLowerCase() == 'cancelled') return false;
  return true;
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

/// Баталгаажуулалт + сервер `POST /ebarimt/return/:orderId`. Амжилттай бол жагсаалтыг шинэчилнэ.
Future<bool> confirmReturnEbarimtReceipt(
  BuildContext context,
  Order order,
) async {
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
      title: const Text('Баримт буцаах'),
      content: Text(
        'eBarimt/POS дээрх баримтыг буцааж, захиалгыг цуцлах уу?\n\n'
        'ДДТД: ${order.ebarimtBillId ?? "—"}\n'
        'Дэлгүүр: ${order.customerName}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Болих'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Буцаах'),
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
    final r = await warehouse.ebarimtReturnOrder(orderId: oid);
    final returnId = (r['returnId'] ?? r['id'] ?? '').toString().trim();
    if (returnId.isNotEmpty) {
      // This endpoint performs the stock restore transaction on the server.
      try {
        await warehouse.ebarimtReturnDone(orderId: oid, returnId: returnId);
      } catch (_) {}
    }
    await orders.fetchOrders(warehouse.dio);
    try {
      await warehouse.refreshProducts();
      if (context.mounted) {
        final products = Provider.of<ProductProvider>(context, listen: false);
        products.setProducts(warehouse.products);
      }
    } catch (_) {}
    if (context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Баримт амжилттай буцаагдлаа')),
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
