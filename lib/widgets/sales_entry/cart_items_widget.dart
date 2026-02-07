import 'package:flutter/material.dart';
import '../../models/sales_item_model.dart';

class CartItemsWidget extends StatelessWidget {
  final List<SalesItem> items;
  final Function(int) onRemoveItem;
  final Function(int, int) onQuantityChanged;
  final double totalAmount;

  const CartItemsWidget({
    super.key,
    required this.items,
    required this.onRemoveItem,
    required this.onQuantityChanged,
    required this.totalAmount,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10B981)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.shopping_cart, color: Color(0xFF10B981)),
              SizedBox(width: 8),
              Text(
                'Сонгосон бараанууд',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(items.length, (index) {
            final item = items[index];
            final quantityController = TextEditingController(
              text: item.quantity.toString(),
            );

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${item.price.toStringAsFixed(0)} ₮ x ${item.quantity} = ${item.total.toStringAsFixed(0)} ₮',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Quantity input field
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: SizedBox(
                      width: 80,
                      child: TextField(
                        controller: quantityController,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF10B981),
                              width: 2,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF10B981),
                              width: 2,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                              color: Color(0xFF059669),
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: Colors.white,
                        ),
                        onTap: () {
                          // Select all text when tapped for easier editing
                          quantityController.selection = TextSelection(
                            baseOffset: 0,
                            extentOffset: quantityController.text.length,
                          );
                        },
                        onChanged: (value) {
                          if (value.isEmpty) return; // Allow empty for editing
                          final newQuantity = int.tryParse(value);
                          if (newQuantity != null && newQuantity > 0) {
                            onQuantityChanged(index, newQuantity);
                          }
                        },
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () {
                      quantityController.dispose();
                      onRemoveItem(index);
                    },
                  ),
                ],
              ),
            );
          }),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Нийт үнэ:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${totalAmount.toStringAsFixed(0)} ₮',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
