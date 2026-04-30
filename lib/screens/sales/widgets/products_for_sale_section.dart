import 'package:flutter/material.dart';

class ProductsForSaleSection extends StatelessWidget {
  const ProductsForSaleSection({
    super.key,
    required this.isLoading,
    required this.searchController,
    required this.productsForSale,
    required this.allProductsForSale,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onShowAll,
  });

  final bool isLoading;
  final TextEditingController searchController;
  final List<dynamic> productsForSale;
  final List<dynamic> allProductsForSale;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shopping_bag_rounded,
                  color: Color(0xFF6366F1), size: 24),
              const SizedBox(width: 12),
              const Text(
                'Зарагдах бараа',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300, width: 1),
            ),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                labelText: '🔍 Бараа хайх',
                hintText: 'Барааны нэр, баркод эсвэл SKU',
                prefixIcon: const Icon(Icons.search,
                    size: 24, color: Color(0xFF6366F1)),
                suffixIcon: searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 20),
                        onPressed: onClearQuery,
                      )
                    : null,
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: Color(0xFF6366F1), width: 2),
                ),
              ),
              style: const TextStyle(fontSize: 16),
              onChanged: onQueryChanged,
            ),
          ),
          const SizedBox(height: 16),
          if (productsForSale.isEmpty && !isLoading)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.search_off,
                        size: 48, color: Colors.grey.shade400),
                    const SizedBox(height: 12),
                    Text(
                      searchController.text.isNotEmpty
                          ? 'Хайлтад тохирох бараа олдсонгүй'
                          : 'Зарагдах бараа олдсонгүй. Refresh дарж дахин оролдоно уу.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            ...productsForSale.map(_ProductTile.new),
            if (allProductsForSale.length > productsForSale.length &&
                searchController.text.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: TextButton(
                    onPressed: onShowAll,
                    child: Text(
                      '${allProductsForSale.length - productsForSale.length} бараа илүү харах',
                      style: const TextStyle(
                        color: Color(0xFF6366F1),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            if (searchController.text.isNotEmpty && productsForSale.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                    '${productsForSale.length} бараа олдлоо',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile(this.product);

  final dynamic product;

  @override
  Widget build(BuildContext context) {
    final stock = (product.stockQuantity ?? 0) as num;
    final price = (product.price ?? 0) as num;

    final bg = switch (stock) {
      > 10 => const Color(0xFFECFDF5),
      > 0 => const Color(0xFFFEF3C7),
      _ => null,
    };

    final fg = switch (stock) {
      > 10 => const Color(0xFF059669),
      > 0 => const Color(0xFFD97706),
      _ => const Color(0xFF475569),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${price.toStringAsFixed(0)} ₮',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (bg ?? Colors.grey.shade200),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'Үлдэгдэл: $stock',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

