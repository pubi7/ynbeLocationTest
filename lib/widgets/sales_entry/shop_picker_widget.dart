import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/shop_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../models/shop_model.dart';

class ShopPickerWidget extends StatelessWidget {
  final String? selectedShopName;
  final TextEditingController controller;
  final Function(String) onShopSelected;
  final Function() onClear;

  const ShopPickerWidget({
    super.key,
    required this.selectedShopName,
    required this.controller,
    required this.onShopSelected,
    required this.onClear,
  });

  void _openShopPicker(BuildContext context, ShopProvider shopProvider) {
    if (shopProvider.shops.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Дэлгүүр сонгох',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFEF4444),
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  controller: scrollController,
                  shrinkWrap: true,
                  itemCount: shopProvider.shops.length,
                  itemBuilder: (ctx, i) {
                    final shop = shopProvider.shops[i];
                    return ListTile(
                      leading: const Icon(Icons.store, color: Color(0xFFEF4444), size: 22),
                      title: Text(shop.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                      subtitle: shop.address.isNotEmpty && shop.address != 'N/A'
                          ? Text(shop.address, style: TextStyle(fontSize: 12, color: Colors.grey[600]), maxLines: 1, overflow: TextOverflow.ellipsis)
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        onShopSelected(shop.name);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<ShopProvider, WarehouseProvider>(
      builder: (context, shopProvider, warehouseProvider, child) {
        final hasError = controller.text.isNotEmpty && 
            !shopProvider.shops.any((shop) => shop.name == controller.text);
        final isSelected = selectedShopName != null;
        
        return GestureDetector(
          onTap: () => _openShopPicker(context, shopProvider),
          child: AbsorbPointer(
            child: TextFormField(
              controller: controller,
              readOnly: true,
              decoration: InputDecoration(
                labelText: '🏪 Дэлгүүр хайж сонгох',
                hintText: shopProvider.shops.isEmpty
                    ? 'Дэлгүүр татагдаагүй байна'
                    : 'Дарж дэлгүүр сонгох',
                prefixIcon: Icon(
                  isSelected ? Icons.check_circle : Icons.store,
                  color: isSelected 
                      ? const Color(0xFF10B981) 
                      : (hasError ? const Color(0xFFDC2626) : Colors.grey[600]),
                ),
                suffixIcon: selectedShopName != null
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: onClear,
                      )
                    : const Icon(Icons.arrow_drop_down, color: Colors.grey),
                filled: true,
                fillColor: isSelected 
                    ? const Color(0xFFF0FDF4) 
                    : (hasError ? const Color(0xFFFEF2F2) : Colors.grey[50]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                      color: isSelected 
                          ? const Color(0xFF10B981) 
                          : (hasError ? const Color(0xFFDC2626) : Colors.grey[300]!),
                      width: isSelected ? 2 : 1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                      color: isSelected 
                          ? const Color(0xFF10B981) 
                          : (hasError ? const Color(0xFFDC2626) : Colors.grey[300]!),
                      width: isSelected ? 2 : 1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                      color: isSelected 
                          ? const Color(0xFF10B981) 
                          : (hasError ? const Color(0xFFDC2626) : Colors.grey[400]!),
                      width: isSelected ? 2 : 2),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                      color: Color(0xFFDC2626), width: 2),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                      color: Color(0xFFDC2626), width: 2),
                ),
              ),
              style: TextStyle(
                  fontSize: 16, 
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? const Color(0xFF059669) : null),
              validator: (value) {
                if (shopProvider.shops.isEmpty) {
                  return 'Дэлгүүр татагдаагүй байна (Settings → Sync)';
                }
                if (value == null || value.isEmpty) {
                  return 'Дэлгүүр сонгоно уу';
                }
                final exists = shopProvider.shops
                    .any((shop) => shop.name == value);
                if (!exists) {
                  return 'Жагсаалтаас сонгоно уу';
                }
                return null;
              },
            ),
          ),
        );
      },
    );
  }
}
