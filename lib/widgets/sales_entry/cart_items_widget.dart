import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../models/sales_item_model.dart';
import '../../providers/product_provider.dart';
import '../../utils/promotion_pricing_utils.dart';

/// Тоо + ₮ нь багана завсар дундаас нь хуваагдахгүй, нэг мөрөнд багтана.
Widget _cartTableMoneyCell(String text, TextStyle style) {
  return Align(
    alignment: Alignment.centerRight,
    child: FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: style,
      ),
    ),
  );
}

class CartItemsWidget extends StatefulWidget {
  final List<SalesItem> items;
  final Function(int) onRemoveItem;
  final void Function(int index, SalesItem updated) onItemChanged;
  final double totalAmount;

  /// Мөрийн дүнгийн нийлбэр (олон ширхэгийн хөнгөлөлтийн өмнө).
  final double lineSubtotalBeforeCartBulk;

  /// Бүх хөнгөлөгдсөн мөр **ижил** хувьтай бол (жишээ 3); олон янз бол null.
  final int? cartBulkDiscountPercentIfUniform;

  /// Барааны ID -> үлдэгдлийн тоо (харуулах зориулалттай)
  final Map<String, int>? stockByProductId;

  const CartItemsWidget({
    super.key,
    required this.items,
    required this.onRemoveItem,
    required this.onItemChanged,
    required this.totalAmount,
    required this.lineSubtotalBeforeCartBulk,
    this.cartBulkDiscountPercentIfUniform,
    this.stockByProductId,
  });

  @override
  State<CartItemsWidget> createState() => _CartItemsWidgetState();
}

class _CartItemsWidgetState extends State<CartItemsWidget> {
  int? _selectedIndex;

  /// `mn_MN` тооны locale зарим төхөөрөмж дээр LocaleDataException өгч болно.
  static final NumberFormat _money = NumberFormat.decimalPattern();
  static const Object _deleteSentinel = Object();

  /// 1+1 зэрэгт: төлөхөөс илүү **үнэгүй** ширхэг — «Бэлэг» баганаар.
  static String _bilgePiecesLabel(SalesItem item) {
    final paid =
        PromotionPricingUtils.effectiveBillablePaidPiecesForPricing(item);
    final free = (item.quantity - paid).clamp(0, item.quantity);
    if (free <= 0) return '—';
    return '$free ш';
  }

  /// «Тоо (ш)» = **төлөх** ширхэг; 1+1 зэрэгт үнэгүйг «Бэлэг»-д тусад нь (нийтийг энд оруулахгүй).
  static String _quantityCellLabel(SalesItem item) {
    final paid =
        PromotionPricingUtils.effectiveBillablePaidPiecesForPricing(item);
    final free = (item.quantity - paid).clamp(0, item.quantity);

    final upb = item.unitsPerBox <= 0 ? 1 : item.unitsPerBox;
    if (item.orderedUnit == 'box' && upb > 1) {
      final fromBoxes = item.orderedQuantity * upb;
      final totalPieces =
          item.quantity > fromBoxes ? item.quantity : fromBoxes;
      if (free > 0) {
        return '$paid ш';
      }
      return '$totalPieces ш (${item.orderedQuantity} хайрцаг)';
    }
    if (free > 0) {
      return '$paid ш';
    }
    return '${item.quantity} ш';
  }

  @override
  void didUpdateWidget(covariant CartItemsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sel = _selectedIndex;
    if (sel == null) return;
    if (sel < 0 || sel >= widget.items.length) {
      _selectedIndex = null;
    }
  }

  Future<void> _openEditDialog(BuildContext context, int index) async {
    final item = widget.items[index];
    final upb = item.unitsPerBox <= 0 ? 1 : item.unitsPerBox;
    final supportsBox = upb > 1;

    Object? result;
    result = await showDialog<Object>(
      context: context,
      builder: (ctx) => _EditCartItemDialog(
        item: item,
        supportsBox: supportsBox,
        unitsPerBox: upb,
        money: _money,
        deleteSentinel: _deleteSentinel,
        availableStock: widget.stockByProductId != null
            ? widget.stockByProductId![item.productId]
            : null,
      ),
    );

    if (!mounted || result == null) return;
    if (identical(result, _deleteSentinel)) {
      widget.onRemoveItem(index);
      setState(() => _selectedIndex = null);
      return;
    }
    if (result is SalesItem) {
      widget.onItemChanged(index, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final productProvider = Provider.of<ProductProvider>(context);

    return Container(
      padding: const EdgeInsets.all(16),
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
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.shopping_cart_rounded,
                  color: Color(0xFF0D9488),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Сонгосон бараанууд',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1F2937),
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Нарийн дэлгэц: хүснэгийг хэвтээ гүйлгэнэ; багана «1…» болж багтахгүй болохоос сэргийлнэ.
                final minTableW = constraints.maxWidth < 420
                    ? 420.0
                    : constraints.maxWidth;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  primary: false,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: minTableW),
                    child: Table(
              columnWidths: const {
                0: FlexColumnWidth(1.75),
                1: FlexColumnWidth(1.0),
                2: FlexColumnWidth(0.85),
                3: FlexColumnWidth(0.95),
                4: FlexColumnWidth(1.15),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: const BoxDecoration(
                    color: Color(0xFF0D9488),
                  ),
                  children: const [
                    _TableHeaderCell('Бараа'),
                    _TableHeaderCell('Нэгж үнэ'),
                    _TableHeaderCell('Тоо (ш)'),
                    _TableHeaderCell('Бэлэг'),
                    _TableHeaderCell('Нийт'),
                  ],
                ),
                ...List.generate(widget.items.length, (index) {
                  final item = widget.items[index];
                  final qtyLabel = _quantityCellLabel(item);
                  final bilgeLabel = _bilgePiecesLabel(item);

                  final selected = _selectedIndex == index;
                  final stock = widget.stockByProductId != null
                      ? (widget.stockByProductId![item.productId])
                      : null;
                  final isLow = stock != null && stock < item.quantity;

                  return TableRow(
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFFEF9C3) // yellow-ish highlight
                          : (index.isEven
                              ? const Color(0xFFF8FAFC)
                              : Colors.white),
                    ),
                    children: [
                      InkWell(
                        onTap: () async {
                          setState(() => _selectedIndex = index);
                          await _openEditDialog(context, index);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.productName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111827),
                                ),
                              ),
                              Builder(
                                builder: (_) {
                                  final p = productProvider
                                      .getProductById(item.productId);
                                  final raw = (p?.promotionText ?? '').trim();
                                  if (raw.isEmpty) {
                                    return const SizedBox.shrink();
                                  }
                                  if (PromotionPricingUtils.parseBuyFree(raw) ==
                                      null) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      raw,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.deepPurple.shade800,
                                        height: 1.2,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              if (item.hasPromotionBenefit) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF8B5CF6)
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: const Color(0xFF8B5CF6)
                                          .withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: const Text(
                                    'Урамшуулалтай',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF6D28D9),
                                    ),
                                  ),
                                ),
                              ],
                              if (stock != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Үлдэгдэл: $stock${isLow ? ' ⚠️' : ''}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: stock == 0
                                        ? Colors.red
                                        : isLow
                                            ? Colors.orange.shade800
                                            : Colors.grey[700],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () async {
                          setState(() => _selectedIndex = index);
                          await _openEditDialog(context, index);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          child: _cartTableMoneyCell(
                            item.price > 0
                                ? '${_money.format(item.price.round())} ₮'
                                : '-',
                            const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () async {
                          setState(() => _selectedIndex = index);
                          await _openEditDialog(context, index);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              qtyLabel,
                              textAlign: TextAlign.right,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF111827),
                              ),
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () async {
                          setState(() => _selectedIndex = index);
                          await _openEditDialog(context, index);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 10,
                          ),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: Text(
                                bilgeLabel,
                                textAlign: TextAlign.right,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: bilgeLabel == '—'
                                      ? const Color(0xFF9CA3AF)
                                      : const Color(0xFF7C3AED),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: () async {
                          setState(() => _selectedIndex = index);
                          await _openEditDialog(context, index);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          child: _cartTableMoneyCell(
                            item.paidQuantity > 0
                                ? '${_money.format((item.finalLineTotal ?? PromotionPricingUtils.payableLineTotalInCart(item, widget.items)).round())} ₮'
                                : '-',
                            const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0D9488),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
          ),
        );
              },
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Дүрмийн тайлбар: мөр дээр дарж засна. «Тоо (ш)» = зөвхөн төлөх ширхэг; «Бэлэг» = 1+1 зэргээр үнэгүй ширхэг. «Нийт» = төлбөрт орох дүн. Доош/хэвтээ гүйлгэнэ. Сервер руу quantity/paidQuantity = төлөх, freeQuantity = үнэгүй.',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
          Divider(color: Colors.grey[200], height: 22),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D9488).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.lineSubtotalBeforeCartBulk - widget.totalAmount >
                    0.01) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Flexible(
                        flex: 2,
                        child: Text(
                          'Мөрийн нийлбэр:',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ),
                      Flexible(
                        flex: 3,
                        child: _cartTableMoneyCell(
                          '${widget.lineSubtotalBeforeCartBulk.toStringAsFixed(0)} ₮',
                          const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Flexible(
                        flex: 2,
                        child: Text(
                          widget.cartBulkDiscountPercentIfUniform != null
                              ? 'Олон ширхэг (урамшуулалтай бараа нийт ≥50 / ≥100): −${widget.cartBulkDiscountPercentIfUniform}%'
                              : 'Олон ширхэг (урамшуулалтай бараа):',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.teal.shade900,
                          ),
                        ),
                      ),
                      Flexible(
                        flex: 3,
                        child: _cartTableMoneyCell(
                          '−${(widget.lineSubtotalBeforeCartBulk - widget.totalAmount).clamp(0.0, 1e15).toStringAsFixed(0)} ₮',
                          TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Colors.teal.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      flex: 2,
                      child: Text(
                        widget.lineSubtotalBeforeCartBulk - widget.totalAmount >
                                0.01
                            ? 'Төлөх нийт:'
                            : 'Нийт үнэ:',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                    ),
                    Flexible(
                      flex: 3,
                      child: _cartTableMoneyCell(
                        '${widget.totalAmount.toStringAsFixed(0)} ₮',
                        const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0D9488),
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

class _EditCartItemDialog extends StatefulWidget {
  const _EditCartItemDialog({
    required this.item,
    required this.supportsBox,
    required this.unitsPerBox,
    required this.money,
    required this.deleteSentinel,
    required this.availableStock,
  });

  final SalesItem item;
  final bool supportsBox;
  final int unitsPerBox;
  final NumberFormat money;
  final Object deleteSentinel;
  final int? availableStock;

  @override
  State<_EditCartItemDialog> createState() => _EditCartItemDialogState();
}

class _EditCartItemDialogState extends State<_EditCartItemDialog> {
  late final TextEditingController _qtyController;
  late final TextEditingController _priceController;
  late final FocusNode _qtyFocus;
  late final FocusNode _priceFocus;
  late bool _byBox;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _byBox = widget.supportsBox && item.orderedUnit == 'box';
    _qtyFocus = FocusNode(debugLabel: 'edit_cart_qty');
    _priceFocus = FocusNode(debugLabel: 'edit_cart_price');
    _qtyController = TextEditingController(
      text: (widget.supportsBox ? item.orderedQuantity : item.quantity).toString(),
    );
    _priceController = TextEditingController(
      text: item.price <= 0 ? '' : widget.money.format(item.price.round()),
    );
  }

  @override
  void dispose() {
    // Best-effort: make sure the IME is closed before the dialog route disposes.
    _qtyFocus.unfocus();
    _priceFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    _qtyFocus.dispose();
    _priceFocus.dispose();
    _qtyController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  /// Dialog route дээр `rootNavigator: true` болон `await delay` нь заримдаа
  /// `pop`-ийн үр дүн алдагдуулдаг тул: sync unfocus → шууд `Navigator.pop`.
  void _closeDialog([Object? result]) {
    _qtyFocus.unfocus();
    _priceFocus.unfocus();
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return AlertDialog(
      title: const Text('Мөр засах'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              item.productName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _qtyController,
              focusNode: _qtyFocus,
              autofocus: false,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: widget.supportsBox && _byBox ? 'Тоо (хайрцаг)' : 'Тоо (ширхэг)',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            if (widget.supportsBox)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _byBox,
                onChanged: (v) => setState(() => _byBox = v ?? false),
                title: const Text('Хайрцагаар'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            const SizedBox(height: 6),
            TextField(
              controller: _priceController,
              focusNode: _priceFocus,
              autofocus: false,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Нэгжийн үнэ (1 ширхэг)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _closeDialog(null),
          child: const Text('Болих'),
        ),
        TextButton(
          onPressed: () => _closeDialog(widget.deleteSentinel),
          child: const Text(
            'Устгах',
            style: TextStyle(color: Color(0xFFDC2626)),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            final rawQty = _qtyController.text.trim();
            final qty = int.tryParse(rawQty) ?? 0;
            if (qty <= 0) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Тоо 0-ээс их байх ёстой'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 2),
                ),
              );
              return;
            }

            final rawPrice = _priceController.text.trim();
            final normalized = rawPrice.replaceAll(RegExp(r'[^0-9.]'), '');
            final parsed = normalized.isEmpty ? null : double.tryParse(normalized);
            final price = (parsed != null && parsed > 0) ? parsed : (item.price > 0 ? item.price : null);
            if (price == null || price <= 0) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Нэгжийн үнэ буруу байна'),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 2),
                ),
              );
              return;
            }

            final orderedUnit = widget.supportsBox && _byBox ? 'box' : 'piece';
            final orderedQty = qty;
            final paidPieces =
                orderedUnit == 'box' ? (orderedQty * widget.unitsPerBox) : orderedQty;

            final product = Provider.of<ProductProvider>(context, listen: false)
                .getProductById(item.productId);
            final promoSource = (item.promotionText?.trim().isNotEmpty ?? false)
                ? item.promotionText!.trim()
                : (product?.promotionText?.trim().isNotEmpty ?? false)
                    ? product!.promotionText!.trim()
                    : '';
            final lineUsesBuyFreePromo =
                (item.promotionText?.trim().isNotEmpty ?? false) ||
                    item.freeQuantity > 0;
            final applyBuyFree = lineUsesBuyFreePromo &&
                promoSource.isNotEmpty &&
                PromotionPricingUtils.parseBuyFree(promoSource) != null;

            final SalesItem updated;
            int? discountOverride;

            if (applyBuyFree) {
              final d = PromotionPricingUtils.decide(
                paidPieces: paidPieces,
                baseUnitPrice: price,
                promotionText: promoSource,
                baseDiscountPercent: item.discountPercent,
                apply: true,
                catalogProductName: item.productName,
              );
              updated = SalesItem(
                productId: item.productId,
                productName: item.productName,
                price: d.unitPriceAfterDiscount,
                quantity: d.totalPieces,
                orderedUnit: orderedUnit,
                orderedQuantity: orderedQty,
                unitsPerBox: widget.unitsPerBox,
                freeQuantity: d.freePieces.clamp(0, d.totalPieces),
                unitPriceExcludesVat: item.unitPriceExcludesVat,
                discountPercent: item.discountPercent,
                promotionText: promoSource,
              );
            } else if (PromotionPricingUtils.isLineOnlyPieceBulkTierProduct(
                item.productName)) {
              final d = PromotionPricingUtils.decide(
                paidPieces: paidPieces,
                baseUnitPrice: price,
                promotionText:
                    promoSource.isEmpty ? null : promoSource,
                baseDiscountPercent: item.discountPercent,
                apply: true,
                catalogProductName: item.productName,
              );
              discountOverride =
                  d.appliedDiscountPercent > 0 ? d.appliedDiscountPercent : null;
              updated = SalesItem(
                productId: item.productId,
                productName: item.productName,
                price: d.unitPriceAfterDiscount,
                quantity: paidPieces,
                orderedUnit: orderedUnit,
                orderedQuantity: orderedQty,
                unitsPerBox: widget.unitsPerBox,
                freeQuantity: 0,
                unitPriceExcludesVat: item.unitPriceExcludesVat,
                discountPercent: discountOverride ?? item.discountPercent,
                promotionText: '50ш+ 3%, 100ш+ 5%',
              );
            } else {
              final outPromo = (item.promotionText?.trim().isNotEmpty ?? false)
                  ? item.promotionText
                  : (product?.promotionText?.trim().isNotEmpty ?? false)
                      ? product!.promotionText
                      : null;
              updated = SalesItem(
                productId: item.productId,
                productName: item.productName,
                price: price,
                quantity: paidPieces,
                orderedUnit: orderedUnit,
                orderedQuantity: orderedQty,
                unitsPerBox: widget.unitsPerBox,
                freeQuantity: 0,
                unitPriceExcludesVat: item.unitPriceExcludesVat,
                discountPercent: item.discountPercent,
                promotionText: outPromo,
              );
            }

            // Best-effort stock validation (нийт ширхэг = төлөх + үнэгүй).
            final stock = widget.availableStock ?? 0;
            if (stock > 0 && updated.quantity > stock) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Үлдэгдэл хүрэлцэхгүй: ${item.productName} (үлдэгдэл $stock, хүссэн ${updated.quantity})',
                  ),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 4),
                ),
              );
              return;
            }

            _closeDialog(updated);
          },
          child: const Text('Хадгалах'),
        ),
      ],
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
        ),
      ),
    );
  }
}
