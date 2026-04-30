import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../models/order_model.dart';
import '../../utils/ebarimt_order_return.dart';

/// Тухайн өдрийн eBarimt баримттай (ДДТД-тай), буцаах боломжтой захиалгууд.
/// Сугалааны дугаар серверт хадгалагддаггүй; ижил урсгалын борлуулалтыг энд шүүж харуулна.
class ReturnableEbarimtOrdersScreen extends StatelessWidget {
  const ReturnableEbarimtOrdersScreen({
    super.key,
    required this.orders,
    this.subtitle,
  });

  final List<Order> orders;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final sub = subtitle?.trim();
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Баримттай захиалга'),
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: orders.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 56, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'Баримт буцаах боломжтой захиалга алга',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Зөвхөн eBarimt-д бүртгэгдсэн, ДДТД авсан, хараахан буцаагаагүй захиалга энд харагдана.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (sub != null && sub.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFCCFBF1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF0D9488).withValues(alpha: 0.25),
                      ),
                    ),
                    child: Text(
                      sub,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.teal.shade900,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                ...orders.map((order) {
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      title: Text(
                        order.customerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text(
                            '${order.orderDate.toString().split('.')[0]} • ${order.status}',
                          ),
                          if (order.ebarimtBillId != null &&
                              order.ebarimtBillId!.isNotEmpty)
                            Text(
                              'ДДТД: ${order.ebarimtBillId}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (orderCanReturnEbarimtReceipt(order))
                            IconButton(
                              icon: const Icon(
                                Icons.undo_rounded,
                                color: Color(0xFFF59E0B),
                              ),
                              tooltip: 'Баримт буцаах',
                              onPressed: () =>
                                  confirmReturnEbarimtReceipt(context, order),
                            ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${order.totalAmount.toStringAsFixed(0)} \u{20ae}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF6366F1),
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      onTap: () => context.push(
                        '/order-details/${order.id}',
                        extra: order,
                      ),
                    ),
                  );
                }),
              ],
            ),
    );
  }
}
