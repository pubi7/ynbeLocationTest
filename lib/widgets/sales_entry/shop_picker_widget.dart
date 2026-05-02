import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/shop_model.dart';
import '../../providers/shop_provider.dart';
import '../../providers/warehouse_provider.dart';

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
      builder: (ctx) => _StoreSelectionSheet(
        shops: shopProvider.shops,
        onShopSelected: (shop) {
          Navigator.pop(ctx);
          onShopSelected(shop.name);
        },
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
                  isSelected ? Icons.check_circle_rounded : Icons.store_rounded,
                  color: isSelected
                      ? const Color(0xFF0D9488)
                      : (hasError ? const Color(0xFFDC2626) : Colors.grey[600]),
                  size: 20,
                ),
                suffixIcon: selectedShopName != null
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded),
                        color: Colors.grey[600],
                        onPressed: onClear,
                      )
                    : Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.grey[500],
                        size: 28,
                      ),
                filled: true,
                fillColor: isSelected
                    ? const Color(0xFFF0FDFA)
                    : (hasError
                        ? const Color(0xFFFEF2F2)
                        : const Color(0xFFFAFAFA)),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: isSelected
                        ? const Color(0xFF0D9488)
                        : (hasError
                            ? const Color(0xFFDC2626)
                            : Colors.grey[300]!),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: isSelected
                        ? const Color(0xFF0D9488)
                        : (hasError
                            ? const Color(0xFFDC2626)
                            : Colors.grey[300]!),
                    width: isSelected ? 2 : 1,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: isSelected
                        ? const Color(0xFF0D9488)
                        : (hasError
                            ? const Color(0xFFDC2626)
                            : Colors.grey[400]!),
                    width: 2,
                  ),
                ),
                errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      const BorderSide(color: Color(0xFFDC2626), width: 2),
                ),
                focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      const BorderSide(color: Color(0xFFDC2626), width: 2),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              style: TextStyle(
                fontSize: 15,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? const Color(0xFF0D9488) : null,
              ),
              validator: (value) {
                if (shopProvider.shops.isEmpty) {
                  return 'Дэлгүүр татагдаагүй байна (Settings → Sync)';
                }
                if (value == null || value.isEmpty) {
                  return 'Дэлгүүр сонгоно уу';
                }
                final exists =
                    shopProvider.shops.any((shop) => shop.name == value);
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

/// Store selection bottom sheet with search
class _StoreSelectionSheet extends StatefulWidget {
  final List<Shop> shops;
  final void Function(Shop) onShopSelected;

  const _StoreSelectionSheet({
    required this.shops,
    required this.onShopSelected,
  });

  @override
  State<_StoreSelectionSheet> createState() => _StoreSelectionSheetState();
}

class _StoreSelectionSheetState extends State<_StoreSelectionSheet> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  List<Shop> get _filteredShops {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.shops;
    return widget.shops.where((shop) {
      final nameMatch = shop.name.toLowerCase().contains(query);
      final addressMatch = shop.address.toLowerCase().contains(query);
      return nameMatch || addressMatch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredShops;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0D9488).withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 48,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFF0D9488).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.store_rounded,
                      color: Color(0xFF0D9488),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Дэлгүүр сонгох',
                          style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1F2937),
                                letterSpacing: -0.3,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${filtered.length} дэлгүүр',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocus,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Дэлгүүр хайх...',
                  prefixIcon: const Icon(Icons.search_rounded,
                      color: Color(0xFF0D9488), size: 22),
                  filled: true,
                  fillColor: const Color(0xFFF0FDFA),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFF0D9488), width: 2),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ),
            Divider(height: 1, color: Colors.grey[200]),
            Flexible(
              child: filtered.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Олдсон дэлгүүр байхгүй',
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey[600],
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final shop = filtered[i];
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => widget.onShopSelected(shop),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0D9488)
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.store_rounded,
                                      color: Color(0xFF0D9488),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          shop.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 15,
                                            color: Color(0xFF1F2937),
                                          ),
                                        ),
                                        if (shop.address.isNotEmpty &&
                                            shop.address != 'N/A') ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            shop.address,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: Colors.grey[400],
                                    size: 24,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
