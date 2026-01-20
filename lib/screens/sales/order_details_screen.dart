import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/order_model.dart';
import '../../providers/order_provider.dart';

class OrderDetailsScreen extends StatelessWidget {
  final String orderId;
  final Order? order;

  const OrderDetailsScreen({
    super.key,
    required this.orderId,
    this.order,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = order ?? context.watch<OrderProvider>().getOrderById(orderId);

    if (resolved == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Захиалгын дэлгэрэнгүй'),
          backgroundColor: const Color(0xFF3B82F6),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Захиалга олдсонгүй')),
      );
    }

    final o = resolved;
    final dateText = MaterialLocalizations.of(context).formatMediumDate(o.orderDate);
    final timeText = MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(o.orderDate));

    Color statusColor(String s) => switch (s.toLowerCase()) {
          'pending' => const Color(0xFFF59E0B),
          'confirmed' => const Color(0xFF3B82F6),
          'delivered' => const Color(0xFF10B981),
          'cancelled' => const Color(0xFFEF4444),
          _ => const Color(0xFF64748B),
        };

    final sc = statusColor(o.status);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Захиалгын дэлгэрэнгүй'),
        backgroundColor: const Color(0xFF3B82F6),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          o.customerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: sc.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          o.status,
                          style: TextStyle(color: sc, fontWeight: FontWeight.w800, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _kv('Огноо / Цаг', '$dateText • $timeText'),
                  _kv('Утас', o.customerPhone),
                  _kv('Хаяг', o.customerAddress),
                  if (o.notes != null && o.notes!.trim().isNotEmpty) _kv('Тэмдэглэл', o.notes!.trim()),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Items
            Text(
              'Авсан бараа',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: o.items.length,
                separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (context, i) {
                  final it = o.items[i];
                  return Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                it.productName,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${it.quantity} ширхэг × ${it.unitPrice.toStringAsFixed(0)} ₮',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${it.totalPrice.toStringAsFixed(0)} ₮',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Total
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF3B82F6).withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Нийт дүн', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(
                    '${o.totalAmount.toStringAsFixed(0)} ₮',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF3B82F6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

