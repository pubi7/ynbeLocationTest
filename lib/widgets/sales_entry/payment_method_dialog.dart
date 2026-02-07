import 'package:flutter/material.dart';

class PaymentMethodDialog {
  static void show(
    BuildContext context, {
    required Function(String) onPaymentSelected,
    String? shopName,
    double? totalAmount,
    double? maxPurchaseAmount,
  }) {
    final hasLimit = maxPurchaseAmount != null && maxPurchaseAmount > 0;
    final overLimit = hasLimit && totalAmount != null && totalAmount > maxPurchaseAmount!;

    if (!overLimit) {
      _showPaymentOptions(context, onPaymentSelected);
      return;
    }

    // Show warning dialog first
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Анхааруулга'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Дэлгүүр: ${shopName ?? 'Unknown'}'),
            const SizedBox(height: 8),
            Text('Дээд хэмжээ: ${maxPurchaseAmount!.toStringAsFixed(0)} ₮'),
            Text('Одоогийн нийт: ${totalAmount!.toStringAsFixed(0)} ₮'),
            const SizedBox(height: 8),
            const Text('Нийт дүн дээд хэмжээнээс хэтэрсэн байна. Үргэлжлүүлэх үү?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Цуцлах'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showPaymentOptions(context, onPaymentSelected);
            },
            child: const Text('Үргэлжлүүлэх'),
          ),
        ],
      ),
    );
  }

  static void _showPaymentOptions(
    BuildContext context,
    Function(String) onPaymentSelected,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Төлбөрийн төрөл сонгох'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPaymentOption(
              context,
              'Бэлэн',
              Icons.money_rounded,
              const Color(0xFF10B981),
              () {
                Navigator.pop(context);
                onPaymentSelected('бэлэн');
              },
            ),
            const SizedBox(height: 12),
            _buildPaymentOption(
              context,
              'Данс',
              Icons.account_balance_wallet_rounded,
              const Color(0xFF3B82F6),
              () {
                Navigator.pop(context);
                onPaymentSelected('данс');
              },
            ),
            const SizedBox(height: 12),
            _buildPaymentOption(
              context,
              'Зээл',
              Icons.credit_card_rounded,
              const Color(0xFF8B5CF6),
              () {
                Navigator.pop(context);
                onPaymentSelected('зээл');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
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
