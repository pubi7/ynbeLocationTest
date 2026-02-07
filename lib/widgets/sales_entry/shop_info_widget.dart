import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/shop_provider.dart';

class ShopInfoWidget extends StatelessWidget {
  final String? selectedShopName;
  final double totalAmount;

  const ShopInfoWidget({
    super.key,
    required this.selectedShopName,
    required this.totalAmount,
  });

  @override
  Widget build(BuildContext context) {
    if (selectedShopName == null) return const SizedBox.shrink();

    return Consumer<ShopProvider>(
      builder: (context, shopProvider, _) {
        final shop = shopProvider.getShopByName(selectedShopName!);
        if (shop == null) return const SizedBox.shrink();
        
        // Always show registration number field, even if empty
        final regText = shop.registrationNumber?.isNotEmpty == true
            ? shop.registrationNumber!
            : null;
        final phoneText = shop.phone.isNotEmpty ? shop.phone : null;
        final addressText = shop.address.isNotEmpty && shop.address != 'N/A'
            ? shop.address
            : null;
        final maxPurchase = shop.maxPurchaseAmount;
        final hasLimit = maxPurchase != null && maxPurchase > 0;
        final overLimit = hasLimit && totalAmount > maxPurchase;
        
        return Container(
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF10B981), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
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
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.store,
                      color: Color(0xFF10B981),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Сонгосон дэлгүүр',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          shop.name,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              const SizedBox(height: 12),
              
              // Бүртгэлийн дугаар - Always show this field
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.badge_outlined,
                      size: 18,
                      color: regText != null ? const Color(0xFF6366F1) : Colors.grey[400],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Бүртгэлийн дугаар',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            regText ?? 'Мэдээлэл байхгүй',
                            style: TextStyle(
                              fontSize: 14,
                              color: regText != null
                                  ? const Color(0xFF1F2937)
                                  : Colors.grey[500],
                              fontWeight: regText != null
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              fontStyle: regText == null ? FontStyle.italic : FontStyle.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              // Утас
              if (phoneText != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.phone, size: 18, color: Color(0xFF6366F1)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Утас',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              phoneText,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF1F2937),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              
              // Хаяг
              if (addressText != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.place, size: 18, color: Color(0xFF6366F1)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Хаяг',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              addressText,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Color(0xFF1F2937),
                              ),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 12),
              
              // Худалдан авалтын хязгаар
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.shopping_bag_outlined,
                    size: 18,
                    color: overLimit
                        ? const Color(0xFFDC2626)
                        : const Color(0xFF6366F1),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '1 удаагийн худалдан авалт',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasLimit ? '${maxPurchase.toStringAsFixed(0)} ₮' : 'Хязгааргүй',
                          style: TextStyle(
                            fontSize: 16,
                            color: overLimit
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF10B981),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              if (overLimit)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFDC2626).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_rounded,
                          color: Color(0xFFDC2626),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Нийт дүн дээд хэмжээнээс хэтэрсэн байна',
                            style: TextStyle(
                              fontSize: 13,
                              color: const Color(0xFFDC2626),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
