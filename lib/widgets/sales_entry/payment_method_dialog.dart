import 'package:flutter/material.dart';

export 'TinDugaar.dart' show CustomerEbarimtInfo;

/// Төлбөрийн төрөл сонгох - зөвхөн төлбөрийн төрөл, customer info-г success дээр асууна
class PaymentMethodDialog {
  static void show(
    BuildContext context, {
    required Function(String paymentMethod) onPaymentSelected,
    String? shopName,
    double? totalAmount,
    double? maxPurchaseAmount,
  }) {
    final hasLimit = maxPurchaseAmount != null &&
        totalAmount != null &&
        totalAmount > maxPurchaseAmount;

    if (!hasLimit) {
      _showPaymentOptionsDialog(
        context,
        onPaymentSelected: onPaymentSelected,
        shopName: shopName,
        totalAmount: totalAmount,
        maxPurchaseAmount: maxPurchaseAmount,
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Анхааруулга'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Дэлгүүр: ${shopName ?? 'Unknown'}'),
            const SizedBox(height: 8),
            Text('Дээд хэмжээ: ${maxPurchaseAmount.toStringAsFixed(0)} ₮'),
            Text('Одоогийн нийт: ${totalAmount.toStringAsFixed(0)} ₮'),
            const SizedBox(height: 8),
            const Text(
                'Нийт дүн дээд хэмжээнээс хэтэрсэн байна. Үргэлжлүүлэх үү?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Цуцлах'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showPaymentOptionsDialog(
                context,
                onPaymentSelected: onPaymentSelected,
                shopName: shopName,
                totalAmount: totalAmount,
                maxPurchaseAmount: maxPurchaseAmount,
              );
            },
            child: const Text('Үргэлжлүүлэх'),
          ),
        ],
      ),
    );
  }

  static void _showPaymentOptionsDialog(
    BuildContext context, {
    required Function(String paymentMethod) onPaymentSelected,
    String? shopName,
    double? totalAmount,
    double? maxPurchaseAmount,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Төлбөрийн төрөл сонгох'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPaymentOption(
              ctx,
              'Бэлэн',
              Icons.money_rounded,
              const Color(0xFF10B981),
              () {
                Navigator.pop(ctx);
                onPaymentSelected('бэлэн');
              },
            ),
            const SizedBox(height: 12),
            _buildPaymentOption(
              ctx,
              'Данс',
              Icons.account_balance_wallet_rounded,
              const Color(0xFF3B82F6),
              () {
                Navigator.pop(ctx);
                onPaymentSelected('данс');
              },
            ),
            const SizedBox(height: 12),
            _buildPaymentOption(
              ctx,
              'Зээл',
              Icons.credit_card_rounded,
              const Color(0xFF8B5CF6),
              () {
                Navigator.pop(ctx);
                onPaymentSelected('зээл');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Цуцлах'),
          ),
        ],
      ),
    );
  }

  static Widget _buildPaymentOption(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
