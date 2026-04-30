import 'package:flutter/material.dart';
import '../../models/sales_item_model.dart';

class CartItemsWidget extends StatelessWidget {
  final List<SalesItem> items;
  final Function(int) onRemoveItem;
  final void Function(int index, String unit, int value) onQuantityChanged;
  final double totalAmount;

  /// Барааны ID -> үлдэгдлийн тоо (харуулах зориулалттай)
  final Map<String, int>? stockByProductId;

  const CartItemsWidget({
    super.key,
    required this.items,
    required this.onRemoveItem,
    required this.onQuantityChanged,
    required this.totalAmount,
    this.stockByProductId,
  });

  static Widget _qtyField({
    required String label,
    required int initialValue,
    required Color accent,
    required ValueChanged<String> onChanged,
  }) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: SizedBox(
        width: 92,
        child: TextFormField(
          initialValue: initialValue.toString(),
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: accent,
          ),
          decoration: InputDecoration(
            labelText: label,
            floatingLabelBehavior: FloatingLabelBehavior.always,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accent, width: 2),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accent.withValues(alpha: 0.5), width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accent, width: 2),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
          onChanged: onChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF0D9488).withValues(alpha: 0.35),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0D9488).withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.shopping_cart_rounded,
                  color: Color(0xFF0D9488),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Сонгосон бараанууд',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...List.generate(items.length, (index) {
            final item = items[index];
            final upb = item.unitsPerBox <= 0 ? 1 : item.unitsPerBox;
            final supportsBox = upb > 1;
            final boxes =
                supportsBox ? (item.quantity ~/ upb) : (item.orderedQuantity);
            final extraPieces = supportsBox ? (item.quantity % upb) : 0;
            final pieces = item.quantity;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFF0FDFA),
                    const Color(0xFFF8FAFC),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            Text(
                              item.productName,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            if (item.hasPromotionBenefit)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFF8B5CF6)
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                                child: const Text(
                                  'Урамшуулалтай',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF6D28D9),
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          () {
                            if (supportsBox) {
                              final combo =
                                  '$boxes хайрцаг${extraPieces > 0 ? ' $extraPieces ширхэг' : ''} = $pieces ширхэг';
                              if (item.freeQuantity > 0) {
                                return '$combo (+${item.freeQuantity} үнэгүй 1+1)';
                              }
                              return combo;
                            }

                            if (item.freeQuantity > 0) {
                              return '$pieces ширхэг (+${item.freeQuantity} үнэгүй 1+1, нийт ${item.quantity} ш)';
                            }
                            return '$pieces ширхэг';
                          }(),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (stockByProductId != null &&
                            stockByProductId!.containsKey(item.productId)) ...[
                          const SizedBox(height: 4),
                          Builder(
                            builder: (context) {
                              final stock =
                                  stockByProductId![item.productId] ?? 0;
                              final isLow = stock < item.quantity;
                              return Text(
                                'Үлдэгдэл: $stock ширхэг${isLow ? ' ⚠️' : ''}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: stock == 0
                                      ? Colors.red
                                      : isLow
                                          ? Colors.orange.shade700
                                          : Colors.grey[700],
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (!supportsBox)
                    _qtyField(
                      label: 'Ширхэг',
                      initialValue: pieces,
                      accent: const Color(0xFF0D9488),
                      onChanged: (value) {
                        if (value.isEmpty) return;
                        final newPieces = int.tryParse(value);
                        if (newPieces != null && newPieces >= 0) {
                          onQuantityChanged(index, 'piece', newPieces);
                        }
                      },
                    )
                  else
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _qtyField(
                          label: 'Хайрцаг',
                          initialValue: boxes,
                          accent: const Color(0xFF6366F1),
                          onChanged: (value) {
                            if (value.isEmpty) return;
                            final newBoxes = int.tryParse(value);
                            if (newBoxes != null && newBoxes >= 0) {
                              onQuantityChanged(index, 'box', newBoxes);
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        _qtyField(
                          label: 'Ширхэг',
                          initialValue: extraPieces,
                          accent: const Color(0xFF0D9488),
                          onChanged: (value) {
                            if (value.isEmpty) return;
                            final newExtra = int.tryParse(value);
                            if (newExtra != null && newExtra >= 0) {
                              onQuantityChanged(index, 'piece', newExtra);
                            }
                          },
                        ),
                      ],
                    ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        onRemoveItem(index);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          color: Color(0xFFDC2626),
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          Divider(color: Colors.grey[200], height: 24),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF0D9488).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Нийт үнэ:',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                ),
                Text(
                  '${totalAmount.toStringAsFixed(0)} ₮',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0D9488),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
