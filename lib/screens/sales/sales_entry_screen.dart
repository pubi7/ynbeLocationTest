import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/sales_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/shop_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../services/sugalaanii_dugaar.dart';
import '../../providers/order_provider.dart';
import '../../utils/role_utils.dart';
import '../../utils/order_schedule_utils.dart';
import '../../utils/warehouse_order_backend_submit_one_file.dart';
import '../../models/sales_model.dart';
import '../../models/sales_item_model.dart';
import '../../models/product_model.dart';
import '../../utils/product_active_utils.dart';
import '../../utils/promotion_pricing_utils.dart';
import '../../widgets/hamburger_menu.dart';
import '../../widgets/go_pop_scope.dart';
import '../../widgets/sales_entry/shop_picker_widget.dart';
import '../../widgets/sales_entry/shop_info_widget.dart';
import '../../widgets/sales_entry/cart_items_widget.dart';
import '../../widgets/sales_entry/payment_method_dialog.dart';
import '../../widgets/sales_entry/success_receipt_dialog.dart';

class SalesEntryScreen extends StatefulWidget {
  const SalesEntryScreen({super.key});

  @override
  State<SalesEntryScreen> createState() => _SalesEntryScreenState();
}

class _SalesEntryScreenState extends State<SalesEntryScreen> {
  final _pageScrollController = ScrollController();
  final _productSearchSectionKey = GlobalKey();
  final _cartSectionKey = GlobalKey();
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  final _productSearchController = TextEditingController();
  final _addQtyController = TextEditingController(text: '1');
  late final TextEditingController _shopFieldController;
  bool _shownProductCounts = false;

  String? _selectedShopName;
  String? _selectedShopId; // Use stable ID when pushing orders
  _SalesEntryMode? _mode;
  bool _askedEntryMode = false;

  // Олон бараа сонгох
  List<SalesItem> _selectedItems = [];
  Set<String> _selectedProductIds = {}; // For multi-select
  Product? _currentProduct;
  final Map<String, int> _productQuantities =
      {}; // Store quantities for each product
  final Map<String, String> _productUnitModes = {}; // 'piece' | 'box'
  final Map<String, bool> _productUsePromotion =
      {}; // true = use promotion (1+1), false/null = don't use

  bool _isLoading = false;
  bool _shopLoadAttempted = false;

  @override
  void initState() {
    super.initState();
    _notesController.addListener(_onNotesChangedRefreshCartLocks);
    _shopFieldController = TextEditingController(text: _selectedShopName ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Mode сонголтыг initState дээр хүчээр асуухгүй.
      // Учир нь authProvider.userRole заримдаа энд хоосон байж болно (ачаалж дуусаагүй).
      // Role бэлэн болмогц build дээр нэг удаа шийднэ.

      final warehouseProvider =
          Provider.of<WarehouseProvider>(context, listen: false);
      if (!warehouseProvider.connected) return;

      final productProvider =
          Provider.of<ProductProvider>(context, listen: false);
      final shopProvider = Provider.of<ShopProvider>(context, listen: false);
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Always refresh shops when entering Record Sale so дэлгүүрийн мэдээлэл is visible
      await warehouseProvider.refreshShops(authProvider: authProvider);
      if (mounted) shopProvider.setShops(warehouseProvider.shops);

      // Always refresh products on entry so we can enforce the desired
      // active/inactive view even if we previously cached the list.
      try {
        debugPrint('[SalesEntry] Refreshing products from warehouse...');
        await warehouseProvider.refreshProducts(includeInactive: true);
        if (mounted) {
          final all = warehouseProvider.products;
          final activeCount = all.where((p) => isProductActive(p)).length;
          final inactiveCount = all.length - activeCount;

          if (kDebugMode) {
            debugPrint('[SalesEntry][debug] products total=${all.length}');
            for (final p in all.take(3)) {
              debugPrint(
                  '[SalesEntry][debug] sample: ${p.name} id=${p.id} isActive=${p.isActive}');
            }
          }

          final activeOnly =
              all.where((p) => isProductActive(p)).toList();
          productProvider.setProducts(activeOnly);
          debugPrint(
              '[SalesEntry] Loaded ${activeOnly.length} active products');

          if (!_shownProductCounts) {
            _shownProductCounts = true;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Бараа: Идэвхтэй $activeCount, Идэвхгүй $inactiveCount (нийт ${all.length})',
                ),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('[SalesEntry] Product refresh failed, using cached list: $e');
        if (!mounted) return;
        final cached = productProvider.products;
        final activeCount = cached.where((p) => isProductActive(p)).length;
        final inactiveCount = cached.length - activeCount;
        final activeOnly = cached.where((p) => isProductActive(p)).toList();
        if (activeOnly.length != cached.length) {
          productProvider.setProducts(activeOnly);
          debugPrint(
              '[SalesEntry] Filtered cached list to ${activeOnly.length} active products');
        }

        if (!_shownProductCounts) {
          _shownProductCounts = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Бараа (cache): Идэвхтэй $activeCount, Идэвхгүй $inactiveCount (нийт ${cached.length})',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    });
  }

  Future<_SalesEntryMode?> _askEntryMode() {
    return showDialog<_SalesEntryMode>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Sales'),
        content: const Text('Ямар үйлдэл хийх вэ?'),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context, _SalesEntryMode.orderOnly),
            icon: const Icon(Icons.shopping_cart_checkout_rounded),
            label: const Text('Хүргэлт (захиалга)'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, _SalesEntryMode.delivery),
            icon: const Icon(Icons.local_shipping_rounded),
            label: const Text('Газар дээр (хэвлэх)'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _notesController.removeListener(_onNotesChangedRefreshCartLocks);
    _pageScrollController.dispose();
    _shopFieldController.dispose();
    _notesController.dispose();
    _productSearchController.dispose();
    _addQtyController.dispose();
    super.dispose();
  }

  /// Дэлгүүр сонгосон үед тухайн дэлгүүрийн үнэ, эсвэл барааны үндсэн үнэ
  double _getProductPrice(Product product) {
    final shopProvider = Provider.of<ShopProvider>(context, listen: false);
    final shop = _selectedShopName != null
        ? shopProvider.getShopByName(_selectedShopName!)
        : null;
    return product.getPiecePriceForCustomerType(shop?.customerTypeId);
  }

  /// Дэлгэцэнд: сонгосон нэгж (ширхэг / хайрцаг)-ийн үнэ.
  double _getProductDisplayPriceForUnit(Product product, String orderedUnit) {
    final shopProvider = Provider.of<ShopProvider>(context, listen: false);
    final shop = _selectedShopName != null
        ? shopProvider.getShopByName(_selectedShopName!)
        : null;
    return product.getUnitPriceForOrderedUnit(
        shop?.customerTypeId, orderedUnit);
  }

  void _onShopSelected(String shopName) {
    // Дэлгүүрийн регистр (TIN/регистр) буруу эсэхийг сонгох мөчид анхааруулна.
    // Буруу байсан ч дэлгүүр сонголтыг болиулахгүй — зөвхөн сануулна.
    try {
      final shopProvider = Provider.of<ShopProvider>(context, listen: false);
      final s = shopProvider.getShopByName(shopName);
      final reg = (s?.registrationNumber ?? '').trim();
      final normalized = reg.replaceAll(RegExp(r'[\s\-\._/\\]'), '');
      // Ихэнх тохиолдолд: байгууллагын регистр=7 орон, ТТД/TIN=11-12 орон.
      final ok = normalized.isNotEmpty &&
          (RegExp(r'^\d{7}$').hasMatch(normalized) ||
              RegExp(r'^\d{11,12}$').hasMatch(normalized));
      if (!ok && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '⚠️ Дэлгүүрийн регистр/ТТД буруу байна. Шалгана уу.\n'
                'Дэлгүүр: $shopName'
                '${reg.isNotEmpty ? '\nОдоогийн утга: $reg' : ''}',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 5),
            ),
          );
        });
      }
    } catch (_) {}

    setState(() {
      _selectedShopName = shopName;
      _shopFieldController.text = shopName;
      // Persist selected shop ID to avoid ambiguous name matching during save.
      final shopProvider = Provider.of<ShopProvider>(context, listen: false);
      _selectedShopId = shopProvider.getShopByName(shopName)?.id;

      // Дэлгүүр солигдоход сагсан дахь бараануудын үнийг шинэ дэлгүүрийн
      // customerTypeId-д тааруулж дахин тооцоолно.
      if (_selectedItems.isNotEmpty) {
        final productProvider =
            Provider.of<ProductProvider>(context, listen: false);
        _selectedItems = _selectedItems.map((it) {
          final p = productProvider.getProductById(it.productId);
          if (p == null) return it;
          final newPrice = _getProductPrice(p);
          if (newPrice == it.price) return it;
          return SalesItem(
            productId: it.productId,
            productName: it.productName,
            price: newPrice,
            quantity: it.quantity,
            freeQuantity: it.freeQuantity,
            unitPriceExcludesVat: it.unitPriceExcludesVat,
            discountPercent: p.discountPercent ?? it.discountPercent,
            promotionText: (p.promotionText?.trim().isNotEmpty ?? false)
                ? p.promotionText
                : it.promotionText,
          );
        }).toList();
        _applyFinalPricingToCart();
      }
    });
    _checkShopCreditStatus(shopName);

    // After selecting a shop, auto-scroll down to the product search section.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _productSearchSectionKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        alignment: 0.08,
      );
    });
  }

  void _onShopCleared() {
    setState(() {
      _selectedShopName = null;
      _selectedShopId = null;
      _shopFieldController.clear();
    });
  }

  void _onNotesChangedRefreshCartLocks() {
    if (_mode == _SalesEntryMode.orderOnly) return;
    if (_selectedItems.isEmpty) return;
    if (!mounted) return;
    setState(_applyFinalPricingToCart);
  }

  /// Тэмдэглэлийн «N%» захиалгын илгээлтэд орох эсэх ([applyDiscountFromNotes])-тай тааруулна.
  double _noteMultiplierForLockedCartPricing({
    required bool applyDiscountFromNotes,
  }) {
    if (!applyDiscountFromNotes) return 1.0;
    final p = WarehouseOrderBackendSubmitOneFile.parsePercentFromNotes(
      _notesController.text.trim(),
    );
    if (p == null) return 1.0;
    return (1.0 - p / 100.0).clamp(0.0, 1.0);
  }

  /// Сагсны мөр бүрт [SalesItem.finalUnitPrice] / [finalLineTotal] (UI-ийн эцсийн үнэ).
  void _applyFinalPricingToCart() {
    if (_selectedItems.isEmpty) return;
    final useNotes = _mode != _SalesEntryMode.orderOnly;
    final mult = _noteMultiplierForLockedCartPricing(
      applyDiscountFromNotes: useNotes,
    );
    _selectedItems = PromotionPricingUtils.applyFinalPricingToCart(
      List<SalesItem>.from(_selectedItems),
      noteMultiplier: mult,
    );
  }

  void _showShopRequiredSnack() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Эхлээд дэлгүүр сонгоно уу. Үнэ, хөнгөлөлт зөв тооцогдохын тулд шаардлагатай.',
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.orange.shade800,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Мөрийн «Нийт» баганын нийлбэр ([PromotionPricingUtils.payableLineTotalInCart]).
  double get _cartLineSubtotal {
    final items = _selectedItems;
    if (items.isEmpty) return 0;
    final resolved =
        items.map(PromotionPricingUtils.resolveLinePromotion).toList();
    final paidList = resolved.map((r) => r.paidPieces).toList();
    final tierBase = paidList.fold<int>(0, (a, b) => a + b);
    var sum = 0.0;
    for (var i = 0; i < items.length; i++) {
      sum += PromotionPricingUtils.payableLineTotalInCart(
        items[i],
        cartWidePaidPiecesTotal: tierBase,
        effectivePaidPieces: paidList[i],
        isBuyOneGetOne: resolved[i].isBogo,
      );
    }
    return sum;
  }

  /// Сагсны 50+/100+ tier суурь: бүх мөрийн төлөх ширхэгийн нийлбэр.
  int get _cartBulkTierPaidPiecesSum =>
      PromotionPricingUtils.cartWideBillablePaidPiecesSum(_selectedItems);

  /// Тодорхой барааны түр мөрийг сагсанд оруулж [cartWideBillablePaidPiecesSum] тооцох.
  int _cartWidePaidPiecesTotalWithProvisionalLine({
    required Product p,
    required String? mergedPromo,
    required int physicalPieces,
    required int replaceIndex,
    required int unitsPerBox,
  }) {
    final cart = List<SalesItem>.from(_selectedItems);
    final upb = unitsPerBox <= 0 ? 1 : unitsPerBox;
    final line = SalesItem(
      productId: p.id,
      productName: p.name,
      price: _getProductPrice(p),
      quantity: physicalPieces,
      orderedUnit: 'piece',
      orderedQuantity: physicalPieces,
      unitsPerBox: upb,
      freeQuantity: 0,
      unitPriceExcludesVat: p.unitPriceExcludesVat,
      discountPercent: p.discountPercent,
      promotionText: mergedPromo,
    );
    if (replaceIndex >= 0 && replaceIndex < cart.length) {
      cart[replaceIndex] = line;
    } else {
      cart.add(line);
    }
    return PromotionPricingUtils.cartWideBillablePaidPiecesSum(cart);
  }

  /// Сагсны дэлгэц: tier идэвхтэй бол хувь (эсвэл null).
  int? get _cartBulkUniformDiscountPercentForUi {
    final p = PromotionPricingUtils.cartPaidPiecesBulkDiscountPercent(
      _cartBulkTierPaidPiecesSum,
    );
    return p > 0 ? p : null;
  }

  /// Төлбөрт орох нийт (олон ширхэгийн хөнгөлөлтийг **нэгж** дээр, **мөрийн** тоогоор).
  double get _totalAmount {
    if (_selectedItems.isNotEmpty &&
        _selectedItems.every(
          (e) =>
              e.finalLineTotal != null &&
              e.finalUnitPrice != null,
        )) {
      return _selectedItems.fold<double>(
        0.0,
        (s, e) => s + e.finalLineTotal!,
      );
    }
    final items = _selectedItems;
    final resolved =
        items.map(PromotionPricingUtils.resolveLinePromotion).toList();
    final paidList = resolved.map((r) => r.paidPieces).toList();
    final tierBase = paidList.fold<int>(0, (a, b) => a + b);
    var s = 0.0;
    for (var i = 0; i < items.length; i++) {
      s += PromotionPricingUtils.lineTotalFromDiscountedUnit(
        unitPrice: items[i].price,
        cartBulkMultiplier:
            PromotionPricingUtils.cartBulkPriceMultiplierForCartLine(
          item: items[i],
          eligiblePaidPiecesTotal: tierBase,
          isBuyOneGetOne: resolved[i].isBogo,
        ),
        paidPieces: paidList[i],
      );
    }
    return s;
  }

  /// Баримт / eBarimt: НӨАТ орсон нийт (олон ширхэгийн хөнгөлөлтийг нэгж дээр тооцсон).
  double get _receiptGrossTotal {
    final items = _selectedItems;
    final resolved =
        items.map(PromotionPricingUtils.resolveLinePromotion).toList();
    final paidList = resolved.map((r) => r.paidPieces).toList();
    final tierBase = paidList.fold<int>(0, (a, b) => a + b);
    var s = 0.0;
    for (var i = 0; i < items.length; i++) {
      s += PromotionPricingUtils.lineTotalFromDiscountedUnit(
        unitPrice: items[i].receiptUnitGross,
        cartBulkMultiplier:
            PromotionPricingUtils.cartBulkPriceMultiplierForCartLine(
          item: items[i],
          eligiblePaidPiecesTotal: tierBase,
          isBuyOneGetOne: resolved[i].isBogo,
        ),
        paidPieces: paidList[i],
      );
    }
    return s;
  }

  void _addProductToCart() {
    // Дэлгүүр сонгогдоогүй бол бараа нэмэхгүй
    if (_selectedShopName == null) {
      _showShopRequiredSnack();
      return;
    }

    if (_currentProduct == null) {
      return;
    }

    final p = _currentProduct!;
    // Disallow adding inactive products to cart.
    if (!isProductActive(p)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Идэвхгүй бараа тул нэмэх боломжгүй: ${p.name}'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }
    final upb = (p.unitsPerBox ?? 1) <= 0 ? 1 : (p.unitsPerBox ?? 1);
    final unit = _productUnitModes[p.id] == 'box' ? 'box' : 'piece';
    final orderedQty = int.tryParse(_addQtyController.text.trim()) ??
        _productQuantities[p.id] ??
        1;
    final clampedOrderedQty = orderedQty < 1 ? 1 : orderedQty;
    _productQuantities[p.id] = clampedOrderedQty;
    final paidPiecesInput =
        unit == 'box' ? (clampedOrderedQty * upb) : clampedOrderedQty;
    final mergedPromo =
        PromotionPricingUtils.mergeCatalogPromotionText(p.name, p.promotionText);
    final buyFree = PromotionPricingUtils.parseBuyFree(mergedPromo);
    final applyPromo = _productUsePromotion[p.id] == true;
    int billablePaidForDecide(int physicalPieces) {
      if (!applyPromo || buyFree == null) return physicalPieces;
      return PromotionPricingUtils.billablePaidPiecesForBuyFreePhysical(
        physicalPieces: physicalPieces,
        bf: buyFree,
      );
    }

    final existingIndex = _selectedItems.indexWhere((it) => it.productId == p.id);
    final mergedPhysical = existingIndex >= 0
        ? _selectedItems[existingIndex].quantity + paidPiecesInput
        : paidPiecesInput;
    final cartWideTier = _cartWidePaidPiecesTotalWithProvisionalLine(
      p: p,
      mergedPromo: mergedPromo,
      physicalPieces: existingIndex >= 0 ? mergedPhysical : paidPiecesInput,
      replaceIndex: existingIndex,
      unitsPerBox: upb,
    );

    // Local stock check (best-effort) so user sees immediate feedback.
    final stock = p.stockQuantity;
    if (stock != null) {
      // Нийт **физ** ширхэг; buy+free акцид `decide`-д төлөх тоог тусад нь хувиргана.
      final mergedPaidForDecide = billablePaidForDecide(mergedPhysical);
      final decisionForStock = PromotionPricingUtils.decide(
        paidPieces: mergedPaidForDecide,
        baseUnitPrice: _getProductPrice(p),
        promotionText: mergedPromo,
        baseDiscountPercent: p.discountPercent,
        apply: applyPromo,
        catalogProductName: p.name,
        cartWidePaidPiecesTotal: cartWideTier,
      );
      final requestedTotal = decisionForStock.totalPieces;
      if (requestedTotal > stock) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Үлдэгдэл хүрэлцэхгүй: ${p.name} (үлдэгдэл $stock, шаардлагатай нийт ширхэг $requestedTotal)',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }
    }

    final paidForDecide = billablePaidForDecide(paidPiecesInput);
    final decision = PromotionPricingUtils.decide(
      paidPieces: paidForDecide,
      baseUnitPrice: _getProductPrice(p),
      promotionText: mergedPromo,
      baseDiscountPercent: p.discountPercent,
      apply: applyPromo,
      catalogProductName: p.name,
      cartWidePaidPiecesTotal: cartWideTier,
    );
    final dp = applyPromo ? decision.appliedDiscountPercent : 0;
    final effectiveUnitPrice = decision.unitPriceAfterDiscount;
    final quantity = decision.totalPieces;

    // Ижил бараа байвал тоог нэмэх
    if (existingIndex >= 0) {
      // Ижил бараа байвал тоог нэмэх
      final existingItem = _selectedItems[existingIndex];
      final totalPaidForDecide = billablePaidForDecide(mergedPhysical);
      final d2 = PromotionPricingUtils.decide(
        paidPieces: totalPaidForDecide,
        baseUnitPrice: _getProductPrice(p),
        promotionText: mergedPromo,
        baseDiscountPercent: p.discountPercent,
        apply: applyPromo,
        catalogProductName: p.name,
        cartWidePaidPiecesTotal: cartWideTier,
      );
      final newQty = d2.totalPieces;
      final newFree = d2.freePieces.clamp(0, newQty);
      final newOrderedQty = unit == 'box'
          ? (mergedPhysical ~/ upb).clamp(1, 1 << 30)
          : mergedPhysical;
      _selectedItems[existingIndex] = SalesItem(
        productId: existingItem.productId,
        productName: existingItem.productName,
        price: d2.unitPriceAfterDiscount,
        quantity: newQty,
        orderedUnit: unit,
        orderedQuantity: newOrderedQty,
        unitsPerBox: upb,
        freeQuantity: newFree,
        unitPriceExcludesVat: existingItem.unitPriceExcludesVat,
        discountPercent: d2.appliedDiscountPercent > 0
            ? d2.appliedDiscountPercent
            : null,
        promotionText: applyPromo ? mergedPromo : null,
      );
    } else {
      // Шинэ бараа нэмэх
      final newFree = decision.freePieces.clamp(0, quantity);
      _selectedItems.add(SalesItem(
        productId: p.id,
        productName: p.name,
        price: effectiveUnitPrice,
        quantity: quantity,
        orderedUnit: unit,
        orderedQuantity: clampedOrderedQty,
        unitsPerBox: upb,
        freeQuantity: newFree,
        unitPriceExcludesVat: p.unitPriceExcludesVat,
        discountPercent: dp > 0 ? dp : null,
        promotionText: applyPromo ? mergedPromo : null,
      ));
    }

    setState(() {
      _applyFinalPricingToCart();
      _currentProduct = null;
    });
  }

  void _removeProductFromCart(int index) {
    setState(() {
      if (index < 0 || index >= _selectedItems.length) return;
      final next = List<SalesItem>.from(_selectedItems);
      next.removeAt(index);
      _selectedItems = next;
      if (_selectedItems.isNotEmpty) {
        _applyFinalPricingToCart();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _cartSectionKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: 0.2,
      );
    });
  }

  void _replaceCartItem(int index, SalesItem updated) {
    setState(() {
      if (index < 0 || index >= _selectedItems.length) return;
      final next = List<SalesItem>.from(_selectedItems);
      next[index] = updated;
      _selectedItems = next;
            _applyFinalPricingToCart();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _cartSectionKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        alignment: 0.2,
      );
    });
  }

  /// Check if promotion text contains 1+1 pattern
  bool _hasPromotion(Product product) {
    return PromotionPricingUtils.parseBuyFree(product.promotionText) != null;
  }

  /// Каталогт урамшуулал/хямдралын дохио байвал «Урамшуулал ашиглах» анхнаасаа асаана
  /// (зөвхөн 1+1 parse биш — хувийн %, текстэн bulk, бусад promotion талбар орно).
  bool _catalogPromotionLikelyEnabled(Product p) {
    if ((p.discountPercent ?? 0) > 0) return true;
    if (_hasPromotion(p)) return true;
    if (PromotionPricingUtils.parseBulkDiscount(p.promotionText) != null) {
      return true;
    }
    if ((p.promotionText ?? '').trim().isNotEmpty) return true;
    return false;
  }

  /// Гол дэлгэц дээр бичихэд доор нь санал гаргахгүй; сонголтыг доод самбараас хийнэ.
  Future<void> _openProductPicker() async {
    if (_selectedShopName == null) {
      _showShopRequiredSnack();
      return;
    }

    final productProvider =
        Provider.of<ProductProvider>(context, listen: false);
    final baseList = productProvider.products
        .where((p) => isProductActive(p))
        .toList();
    if (baseList.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Идэвхтэй бараа олдсонгүй.')),
      );
      return;
    }

    Product? picked;
    picked = await showModalBottomSheet<Product?>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) {
        final allItems = List<Product>.from(baseList)
          ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

        final filterController = TextEditingController();
        var promoOnly = false;

        return StatefulBuilder(
          builder: (sheetCtx, setModal) {
            final q = filterController.text.trim().toLowerCase();
            final baseFiltered = promoOnly
                ? allItems.where(_catalogPromotionLikelyEnabled).toList()
                : allItems;
            final items = q.isEmpty
                ? baseFiltered
                : baseFiltered.where((p) {
                    return p.name.toLowerCase().contains(q) ||
                        (p.barcode ?? '').toLowerCase().contains(q) ||
                        (p.productCode ?? '').toLowerCase().contains(q);
                  }).toList();

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(sheetCtx).bottom,
                  left: 16,
                  right: 16,
                  top: 12,
                ),
                child: SizedBox(
                  height: MediaQuery.sizeOf(sheetCtx).height * 0.78,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Бараа сонгох',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            tooltip: 'Хайх',
                            onPressed: () {
                              // Toggle: focus search input
                              Future<void>.delayed(
                                const Duration(milliseconds: 10),
                                () => FocusScope.of(sheetCtx).requestFocus(),
                              );
                            },
                            icon: const Icon(Icons.search),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(sheetCtx).pop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      TextField(
                        controller: filterController,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText: 'Хайлт',
                          hintText: 'Нэр, баркод, код…',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: filterController.text.trim().isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    filterController.clear();
                                    setModal(() {});
                                  },
                                ),
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setModal(() {}),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilterChip(
                            label: const Text('Хямдралтай'),
                            selected: promoOnly,
                            onSelected: (v) => setModal(() => promoOnly = v),
                          ),
                          Text(
                            promoOnly
                                ? 'Илэрц: ${items.length} (хямдралтай)'
                                : 'Илэрц: ${items.length}',
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: items.isEmpty
                            ? Center(
                                child: Text(
                                  'Илэрц олдсонгүй',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              )
                            : ListView.separated(
                                itemCount: items.length,
                                separatorBuilder: (_, __) =>
                                    const Divider(height: 1),
                                itemBuilder: (c, i) {
                                  final p = items[i];
                                  final stock = p.stockQuantity;
                                  final stockLabel = stock != null
                                      ? 'Үлдэгдэл: $stock'
                                      : 'Үлдэгдэл: —';
                                  final stockStyle = TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: stock == null
                                        ? Colors.grey[600]
                                        : stock == 0
                                            ? Colors.red[700]
                                            : Colors.teal[800],
                                  );
                                  return ListTile(
                                    title: Text(p.name),
                                    subtitle: Text(stockLabel, style: stockStyle),
                                    onTap: () => Navigator.of(sheetCtx).pop(p),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || picked == null) return;

    final p = picked;
    setState(() {
      _currentProduct = p;
      // Keep internal value in sync even though search UI is hidden.
      _productSearchController.text = p.name;
      _productQuantities[p.id] = 1;
      _productUnitModes[p.id] = 'piece';
      // 1+1 / урамшуулалтай бараанд анхнаасаа асаана (хэрэглэгч асаахгүй гээд мартахгүй).
      _productUsePromotion[p.id] =
          _productUsePromotion[p.id] ?? _catalogPromotionLikelyEnabled(p);
      _addQtyController.text = '1';
    });
  }

  void _checkShopCreditStatus(String shopName) {
    final salesProvider = Provider.of<SalesProvider>(context, listen: false);
    final shopProvider = Provider.of<ShopProvider>(context, listen: false);

    // Зээлээр авсан төлбөр хийгээгүй эсэхийг шалгах
    final hasUnpaidCredit =
        shopProvider.hasUnpaidCredit(shopName, salesProvider.sales);

    if (hasUnpaidCredit) {
      final unpaidAmount =
          shopProvider.getUnpaidCreditAmount(shopName, salesProvider.sales);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.warning_rounded, color: Colors.orange),
                  const SizedBox(width: 8),
                  const Text('Анхааруулга'),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$shopName дэлгүүрт зээлээр авсан төлбөр хийгээгүй байна.',
                    style: const TextStyle(fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Төлөгдөөгүй дүн: ${unpaidAmount.toStringAsFixed(0)} ₮',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Зээлээр худалдан авалт хийхээсээ өмнө төлбөр хийхэд анхаарна уу.',
                    style: TextStyle(fontSize: 14, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Ойлголоо'),
                ),
              ],
            ),
          );
        }
      });
    }
  }

  void _showPaymentMethodDialog() {
    if (_selectedShopName == null) {
      _showShopRequiredSnack();
      return;
    }
    final shopProvider = Provider.of<ShopProvider>(context, listen: false);
    final shop = shopProvider.getShopByName(_selectedShopName!);

    PaymentMethodDialog.show(
      context,
      onPaymentSelected: _processPurchase,
      shopName: shop?.name ?? _selectedShopName,
      totalAmount: _totalAmount,
      maxPurchaseAmount: shop?.maxPurchaseAmount,
    );
  }

  /// Захиалга (order-only) хадгалах — төлбөрийн төрөл сонгоод backend руу илгээнэ.
  void _showPaymentMethodDialogForOrderOnly() {
    if (_selectedShopName == null) {
      _showShopRequiredSnack();
      return;
    }
    final shopProvider = Provider.of<ShopProvider>(context, listen: false);
    final shop = shopProvider.getShopByName(_selectedShopName!);

    PaymentMethodDialog.show(
      context,
      onPaymentSelected: _createOrderOnlyAndPush,
      shopName: shop?.name ?? _selectedShopName,
      totalAmount: _totalAmount,
      maxPurchaseAmount: shop?.maxPurchaseAmount,
    );
  }

  Future<void> _processPurchase(String paymentMethod) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final role = authProvider.userRole;

      // Agent: баримт/хэвлэлгүй, захиалгыг шууд backend (Weve) руу илгээнэ.
      if (isAgentRole(role)) {
        final pushed = await _submitSaleWithPaymentMethod(paymentMethod);
        if (pushed == null) return;
        if (!mounted) return;
        final today = OrderScheduleUtils.localCalendarDayYyyyMmDd();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Захиалга үүсгэлээ (ID: ${pushed.orderId}).\nЗахиалгын өдөр: $today',
            ),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 4),
          ),
        );
        setState(() {
          _selectedItems.clear();
          _selectedProductIds.clear();
          _productQuantities.clear();
          _productUnitModes.clear();
          _productUsePromotion.clear();
          _currentProduct = null;
          _notesController.clear();
          _productSearchController.clear();
        });
        // Stay on this screen after save; user continues working.
        return;
      }

      // Сервер руу захиалга: зөвхөн success dialog дээр «Хэвлэх» / «Хаах» дарсны дараа
      if (mounted) {
        final savedItems = List<SalesItem>.from(_selectedItems);
        final savedShopName = _selectedShopName ?? 'Дэлгүүр';
        final savedNotes = _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim();
        final savedUser = authProvider.user;
        final shopProvider = Provider.of<ShopProvider>(context, listen: false);
        final shopReg = _selectedShopName != null
            ? shopProvider.getShopByName(_selectedShopName!)?.registrationNumber
            : null;
        final isDelivery = _mode == _SalesEntryMode.delivery;

        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => SuccessReceiptDialog(
            paymentMethod: paymentMethod,
            savedItems: savedItems,
            savedShopName: savedShopName,
            savedNotes: savedNotes,
            salespersonName: savedUser?.name,
            shopRegistrationFromServer:
                shopReg != null && shopReg.trim().isNotEmpty
                    ? shopReg.trim()
                    : null,
            directPosDelivery: isDelivery,
            directPosBaseUrl: isDelivery ? 'http://43.231.115.209:7080' : null,
            // Шууд POS (7080) хэвлэх горим байсан ч Weve сайт руу захиалга үүсгээд илгээнэ.
            onCommitWarehouseOrder: () =>
                _submitSaleWithPaymentMethod(paymentMethod),
            onEbarimtSubmit: (pm, info, oid) =>
                isDelivery ? Future.value() : _sendToEbarimt(pm, info, oid),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        String msg = 'Захиалга backend-д илгээгдэхэд алдаа гарлаа';
        if (e is DioException && e.response?.data != null) {
          final data = e.response!.data;
          if (data is Map && data['message'] != null) {
            msg = data['message'].toString();
          }
        } else if (e.toString().isNotEmpty) {
          msg = 'Алдаа: ${e.toString().split('\n').first}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _createOrderOnlyAndPush(String paymentMethod) async {
    if (_isLoading) return;
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;
    if (_selectedShopName == null) {
      _showShopRequiredSnack();
      return;
    }
    if (_selectedItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сагс хоосон байна. Эхлээд бараа нэмнэ үү.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final locationProvider =
          Provider.of<LocationProvider>(context, listen: false);
      final capturedLoc =
          await locationProvider.refreshLocationForOrderRecording();

      // Захиалга үүсгэх (баримт/хэвлэлгүй) — web site руу шууд илгээнэ.
      // Payment method: user-selected (mapped to backend enum in _pushOrderToWeve).
      final pushed =
          await _pushOrderToWeve(paymentMethod, applyDiscountFromNotes: false);
      if (pushed == null) return;

      final loc = capturedLoc ?? locationProvider.currentLocation;
      if (loc != null) {
        await locationProvider.saveOrderLocation(
          orderId: pushed.orderId,
          location: loc,
          shopName: _selectedShopName,
        );
      }

      if (!mounted) return;
      final today = OrderScheduleUtils.localCalendarDayYyyyMmDd();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Захиалга үүсгэлээ (ID: ${pushed.orderId}).\nЗахиалгын өдөр: $today',
          ),
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 4),
        ),
      );

      setState(() {
        _selectedItems.clear();
        _selectedProductIds.clear();
        _productQuantities.clear();
        _productUnitModes.clear();
        _productUsePromotion.clear();
        _currentProduct = null;
        _notesController.clear();
      });
      // Stay on this screen after save; user continues working.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Алдаа: ${e.toString().split('\n').first}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Захиалга үүсгэсний дараах диалогт дамжуулах мэдээлэл
  Future<({int orderId, String? serverLotteryNumber})?>
      _submitSaleWithPaymentMethod(String paymentMethod) async {
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return null;

    if (_selectedShopName == null) {
      if (mounted) _showShopRequiredSnack();
      return null;
    }

    if (_selectedItems.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сагс хоосон байна. Эхлээд бараа нэмнэ үү.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return null;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final salesProvider = Provider.of<SalesProvider>(context, listen: false);
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);

    // Захиалгын мөчийн борлуулагчийн байршил (газрын зураг дээрх пин) — түр шинэчилна.
    final capturedLoc =
        await locationProvider.refreshLocationForOrderRecording();

    // Одоогийн байршил (GPS эсвэл IP-горим)
    double? latitude;
    double? longitude;
    final locForCoords = capturedLoc ?? locationProvider.currentLocation;
    if (locForCoords != null) {
      latitude = locForCoords.latitude;
      longitude = locForCoords.longitude;
    }

    // Одоогийн IP хаягийг авах
    final ipAddress = locationProvider.currentIpAddress;

    // Эхлээд backend руу захиалга илгээнэ. Үлдэгдэл хүрэлцэхгүй зэргээр цуцлагдвал
    // орон нутгийн борлуулалт бүртгэхгүй — тиймгүй л дахбоард/өнөөдрийн борлуулалт буруу нэмэгдэнэ.
    final pushed =
        await _pushOrderToWeve(paymentMethod, applyDiscountFromNotes: true);
    if (pushed == null) {
      return null;
    }
    final orderId = pushed.orderId;
    final serverLottery = pushed.serverLotteryNumber;

    // Захиалгын байршлыг orderId-тай нь холбоод хадгална (апп дахин ачаалсан ч үлдэнэ).
    final loc = locForCoords;
    if (loc != null) {
      await locationProvider.saveOrderLocation(
        orderId: orderId,
        location: loc,
        shopName: _selectedShopName,
      );
    }

    // Амжилттай: бараа бүрийг тусдаа Sales record болгон нэмнэ (сагсны bulk tier: бүх мөрийн төлөх нийлбэр).
    final tierBase =
        PromotionPricingUtils.cartWideBillablePaidPiecesSum(_selectedItems);
    for (var item in _selectedItems) {
      final bulkMult =
          PromotionPricingUtils.cartBulkPriceMultiplierForCartLine(
        item: item,
        eligiblePaidPiecesTotal: tierBase,
      );
      final sale = Sales(
        id: '${DateTime.now().millisecondsSinceEpoch}_${item.productId}',
        productName: item.productName,
        location: _selectedShopName!,
        salespersonId: authProvider.user?.id ?? '',
        salespersonName: authProvider.user?.name ?? '',
        amount: item.finalLineTotal ??
            PromotionPricingUtils.lineTotalFromDiscountedUnit(
              unitPrice: item.price,
              cartBulkMultiplier: bulkMult,
              paidPieces:
                  PromotionPricingUtils.effectiveBillablePaidPiecesForPricing(
                item,
              ),
            ),
        saleDate: DateTime.now(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        paymentMethod: paymentMethod,
        latitude: latitude,
        longitude: longitude,
        quantity: item.quantity,
        ipAddress: ipAddress,
        warehouseOrderId: orderId,
      );

      await salesProvider.addSale(sale);
    }

    return (orderId: orderId, serverLotteryNumber: serverLottery);
  }

  Future<void> _sendToEbarimt(String paymentMethod,
      CustomerEbarimtInfo customerInfo, int? orderId) async {
    // Ebarimt API руу илгээх мэдээлэл:
    // TinNumber: Хувь хүн - хоосон; Байгуулга - getTinInfo-аас авсан TIN
    // registerNumber: Хувь хүн - хоосон; Байгуулга - оруулсан регистр
    // items: [{ barcode, name, unitPrice, qty, qtyType: 'shirheg'|'kg', totalAmount }]

    final locationName = _selectedShopName ?? 'Дэлгүүр';
    final productProvider =
        Provider.of<ProductProvider>(context, listen: false);

    final tierBase =
        PromotionPricingUtils.cartWideBillablePaidPiecesSum(_selectedItems);
    final items = _selectedItems.map((item) {
      final mult =
          PromotionPricingUtils.cartBulkPriceMultiplierForCartLine(
        item: item,
        eligiblePaidPiecesTotal: tierBase,
      );
      final product = productProvider.getProductById(item.productId);
      final barcode = product?.barcode ?? product?.productCode ?? '';
      // qtyType: ширхгээр эсвэл кг-аар - одоогоор бүгдийг ширхэг
      final qtyType = (product?.netWeight != null && product!.netWeight! > 0)
          ? 'kg'
          : 'shirheg';
      return {
        'barcode': barcode.isNotEmpty ? barcode : item.productId,
        'name': item.productName,
        'unitPrice': PromotionPricingUtils.discountedUnitPrice(
          unitPrice: item.receiptUnitGross,
          cartBulkMultiplier: mult,
        ),
        'qty': PromotionPricingUtils.effectiveBillablePaidPiecesForPricing(item),
        'qtyType': qtyType,
        'totalAmount': PromotionPricingUtils.lineTotalFromDiscountedUnit(
          unitPrice: item.receiptUnitGross,
          cartBulkMultiplier: mult,
          paidPieces:
              PromotionPricingUtils.effectiveBillablePaidPiecesForPricing(item),
        ),
      };
    }).toList();

    final payload = {
      'location': locationName,
      'paymentMethod': paymentMethod,
      'tinNumber': customerInfo.tinNumber ?? '',
      'registerNumber': customerInfo.registerNumber ?? '',
      'customerType': customerInfo.customerType,
      'items': items,
      'totalAmount': _receiptGrossTotal,
    };

    debugPrint('Ebarimt руу илгээж байна:');
    debugPrint('  TinNumber: ${payload['tinNumber']}');
    debugPrint('  registerNumber: ${payload['registerNumber']}');
    debugPrint('  Барааны тоо: ${items.length}');

    // Байгуулга сонгосон үед getTinInfo мэдээллийг Weve website дээр харуулах
    if (customerInfo.customerType == 'Байгуулга' &&
        orderId != null &&
        customerInfo.tinNumber != null &&
        customerInfo.registerNumber != null) {
      try {
        final warehouseProvider =
            Provider.of<WarehouseProvider>(context, listen: false);
        if (warehouseProvider.connected) {
          await warehouseProvider.updateOrderEbarimtInfo(
            orderId: orderId,
            tin: customerInfo.tinNumber!,
            regNo: customerInfo.registerNumber!,
            orgName: customerInfo.companyName,
          );
          debugPrint(
              '✅ getTinInfo мэдээлэл Weve захиалга дээр шинэчлэгдлээ (TIN: ${customerInfo.tinNumber})');
        }
      } catch (e) {
        debugPrint('⚠️ Захиалгыг ebarimt мэдээллээр шинэчлэхэд алдаа: $e');
      }
    }
    for (var item in items) {
      debugPrint(
          '  - ${item['name']}: ${item['qty']} ${item['qtyType']} x ${item['unitPrice']} = ${item['totalAmount']} ₮');
    }
    debugPrint('  Нийт (баримт, НӨАТ орсон): $_receiptGrossTotal ₮');

    // TODO: Бодит Ebarimt receipt API-д илгээх (backend /api/ebarimt/receipt гэх мэт)
    await Future.delayed(const Duration(milliseconds: 500));
  }

  Future<({int orderId, String? serverLotteryNumber})?> _pushOrderToWeve(
    String paymentMethod, {
    required bool applyDiscountFromNotes,
  }) async {
    try {
      final warehouseProvider =
          Provider.of<WarehouseProvider>(context, listen: false);
      final shopProvider = Provider.of<ShopProvider>(context, listen: false);

      if (!warehouseProvider.connected) {
        debugPrint('⚠️  Warehouse backend-тэй холбогдоогүй байна');
        return null;
      }

      // Prefer stable selected shop ID (names can be duplicated / lists can refresh)
      final selectedId = _selectedShopId ??
          shopProvider.getShopByName(_selectedShopName ?? '')?.id;
      final fallbackShop = shopProvider.shops.isNotEmpty
          ? shopProvider.shops.firstWhere(
              (shop) => shop.name == _selectedShopName,
              orElse: () => shopProvider.shops.first,
            )
          : null;
      final rawCustomerId = selectedId ?? fallbackShop?.id;

      // Parse customerId (backend expects int)
      final customerId =
          rawCustomerId == null ? null : int.tryParse(rawCustomerId);
      if (customerId == null) {
        debugPrint('⚠️  Дэлгүүрийн ID буруу байна: $rawCustomerId');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Дэлгүүрийн мэдээлэл буруу байна. Дэлгүүрээ дахин сонгоод дахин оролдоно уу.',
              ),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return null;
      }

      // Хадгалахын өмнө серверээс хамгийн сүүлийн үлдэгдэл/барааны жагсаалт татаж шалгана.
      await warehouseProvider.refreshProducts(includeInactive: true);
      if (!mounted) return null;
      final refreshErr = warehouseProvider.error;
      if (refreshErr != null && refreshErr.trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Үлдэгдэл шалгахын тулд бараа татахад алдаа: $refreshErr',
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        return null;
      }
      if (!warehouseProvider.connected) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Сервертэй холбогдоогүй байна. Дахин нэвтэрнэ үү.'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return null;
      }

      final productProvider =
          Provider.of<ProductProvider>(context, listen: false);
      productProvider.setProducts(
        warehouseProvider.products.where((p) => isProductActive(p)).toList(),
      );

      for (final cart in _selectedItems) {
        final p = productProvider.getProductById(cart.productId);
        if (p == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Бараа олдсонгүй (серверийн жагсаалт): ${cart.productName}. Сагсаас хасаад дахин нэмнэ үү.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return null;
        }
        // If a product is inactive, block order submit with clear message.
        if (!isProductActive(p)) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Идэвхгүй бараа тул захиалга үүсгэх боломжгүй: ${cart.productName}',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return null;
        }
        final stock = p.stockQuantity;
        if (stock != null && cart.quantity > stock) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Үлдэгдэл хүрэлцэхгүй: ${cart.productName} (сервер: $stock ш, сагс: ${cart.quantity} ш нийт)',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return null;
        }
      }

      final notes = _notesController.text.trim();
      final noteMult = _noteMultiplierForLockedCartPricing(
        applyDiscountFromNotes: applyDiscountFromNotes,
      );
      final pricedCart = PromotionPricingUtils.applyFinalPricingToCart(
        List<SalesItem>.from(_selectedItems),
        noteMultiplier: noteMult,
      );
      final items = WarehouseOrderBackendSubmitOneFile.buildItemsFromSalesCart(
        pricedCart,
        applyDiscountFromNotes: applyDiscountFromNotes,
        notesTrimmed: notes,
      );
      WarehouseOrderBackendSubmitOneFile.debugLogBackendOrderItems(
        items,
        productNames: pricedCart.map((e) => e.productName).toList(),
      );

      final backendPaymentMethod =
          WarehouseOrderBackendSubmitOneFile.mapMobilePaymentMethodToBackend(
        paymentMethod,
      );

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      debugPrint('📤 Warehouse backend руу захиалга илгээж байна...');
      debugPrint('   • Нэвтэрсэн хэрэглэгч ID: ${authProvider.user?.id}');
      debugPrint('   • Нэвтэрсэн хэрэглэгч: ${authProvider.user?.name}');
      debugPrint('   • Дэлгүүр ID: $customerId');
      debugPrint('   • Барааны тоо: ${items.length}');
      debugPrint('   • Төлбөрийн төрөл: $backendPaymentMethod');

      // Create order via warehouse backend API
      // Backend uses JWT token's userId as agentId (= mobile logged-in user's ID).
      // orderAcceptanceDate = локал «авсан өдөр» (YYYY-MM-DD); прокси нь orderDate-ийг
      // бүртгэсэн UTC цагаар, deliveryDate-ийг acceptance + role-оор тооцно.
      final role = authProvider.userRole;
      final now = DateTime.now();
      final addDays =
          isManagerRole(role) ? 0 : (now.weekday == DateTime.saturday ? 2 : 1);
      final orderAcceptanceYmd = OrderScheduleUtils.localCalendarDayYyyyMmDd(
        now.add(Duration(days: addDays)),
      );
      final result =
          await WarehouseOrderBackendSubmitOneFile.createOrderWith429Retry(
        () => warehouseProvider.createOrder(
          customerId: customerId,
          items: items,
          orderType: 'Store',
          paymentMethod: backendPaymentMethod,
          notes: notes.isEmpty ? null : notes,
          deliveryDate: null,
          orderAcceptanceDate: orderAcceptanceYmd,
          allowInsufficientStock: false,
        ),
      );

      // Илгээсэн мөрүүдтэй сагсыг тааруулна (дашбоардын орон нутгийн борлуулалт г.м.).
      if (mounted) {
        setState(() {
          _selectedItems = pricedCart;
        });
      }

      debugPrint('✅ Захиалга амжилттай илгээгдлээ!');
      final orderId = (result['order']?['id'] as num?)?.toInt();
      // "Захиалга" (orderOnly): сугалаа/ebarimt/register автоматаар огт дуудахгүй —
      // Weve site руу зөвхөн захиалга л очно.
      //
      // Agent: ямар ч тохиолдолд сугалаа/ebarimt/register автоматаар дуудахгүй.
      // Manager/бусад + "Хүргэлт": вэбтэй ижилээр ebarimt/register-аас сугалаа/ДДТД авч болно.
      final shouldResolveLottery =
          _mode == _SalesEntryMode.delivery && !isAgentRole(authProvider.userRole);
      final String? serverLottery = shouldResolveLottery
          ? await SugalaaniiDugaar.resolveServerLotteryAfterOrderCreated(
              createOrderResult: result,
              orderId: orderId,
              tryRegisterOrder: (id) =>
                  warehouseProvider.tryEbarimtRegisterOrder(id),
            )
          : null;
      debugPrint('   • Order ID: $orderId');
      debugPrint('   • Agent ID (backend): ${result['order']?['agentId']}');
      debugPrint('   • Order Number: ${result['order']?['orderNumber']}');
      debugPrint('🌐 Захиалга web dashboard дээр харагдаж байна!');

      // Refresh orders list so it appears immediately on dashboard/orders screen
      try {
        if (mounted) {
          final orderProvider =
              Provider.of<OrderProvider>(context, listen: false);
          await orderProvider.fetchOrders(warehouseProvider.dio);
          if (orderId != null) {
            orderProvider.patchOrderFreeQuantitiesFromCart(
              orderId: orderId.toString(),
              cart: pricedCart,
            );
          }
          debugPrint('📋 Захиалгын жагсаалт шинэчлэгдлээ');
        }
      } catch (e) {
        debugPrint('⚠️ Захиалгын жагсаалт шинэчлэхэд алдаа: $e');
      }

      // Refresh products to update stock quantities after order
      try {
        await warehouseProvider.refreshProducts();
        if (mounted) {
          final productProvider =
              Provider.of<ProductProvider>(context, listen: false);
          productProvider.setProducts(warehouseProvider.products);
          debugPrint('📦 Барааны үлдэгдэл шинэчлэгдлээ');
        }
      } catch (e) {
        debugPrint('⚠️ Барааны үлдэгдэл шинэчлэхэд алдаа: $e');
      }

      if (orderId == null) return null;
      return (orderId: orderId, serverLotteryNumber: serverLottery);
    } catch (e) {
      debugPrint('❌ Захиалга backend-д илгээхэд алдаа: $e');
      if (mounted) {
        String msg = e.toString();
        if (e is DioException) {
          final data = e.response?.data;
          if (data is Map && data['message'] != null) {
            msg = data['message'].toString();
          } else if (e.message != null && e.message!.trim().isNotEmpty) {
            msg = e.message!.trim();
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authRole = context.watch<AuthProvider>().userRole;
    // Role бэлэн болмогц mode-оо нэг удаа шийднэ:
    // - Agent: диалоггүйгээр шууд "Хүргэлт(захиалга)" = orderOnly
    // - Manager: диалоггүйгээр шууд "Хүргэлт(захиалга)" = orderOnly (Weve site руу)
    // - Бусад: диалог нэг удаа асууна
    if (!_askedEntryMode && _mode == null && authRole.trim().isNotEmpty) {
      _askedEntryMode = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted || _mode != null) return;
        if (isAgentRole(authRole)) {
          setState(() {
            _mode = _SalesEntryMode.orderOnly;
            _applyFinalPricingToCart();
          });
          return;
        }
        if (isManagerRole(authRole)) {
          setState(() {
            _mode = _SalesEntryMode.orderOnly;
            _applyFinalPricingToCart();
          });
          return;
        }
        final picked = await _askEntryMode();
        if (!mounted) return;
        setState(() {
          _mode = picked ?? _SalesEntryMode.delivery;
          _applyFinalPricingToCart();
        });
      });
    }

    return GoPopScope(
      fallbackRoute: GoPopScope.homeRouteFor(context),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Борлуулагч'),
          backgroundColor: Colors.blue,
          foregroundColor: Colors.white,
          elevation: 1,
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => Scaffold.of(context).openDrawer(),
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.go(GoPopScope.homeRouteFor(context)),
            ),
          ],
        ),
        drawer: const HamburgerMenu(),
        bottomNavigationBar: null,
        body: SingleChildScrollView(
        controller: _pageScrollController,
        padding: const EdgeInsets.all(12),
        physics: const AlwaysScrollableScrollPhysics(),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
                          // Дэлгүүр сонгох
                          Consumer2<ShopProvider, WarehouseProvider>(
                            builder: (context, shopProvider, warehouseProvider,
                                child) {
                              if (shopProvider.shops.isEmpty &&
                                  warehouseProvider.connected &&
                                  !_shopLoadAttempted) {
                                _shopLoadAttempted = true;
                                WidgetsBinding.instance
                                    .addPostFrameCallback((_) async {
                                  if (!mounted) return;
                                  final wp = Provider.of<WarehouseProvider>(
                                      context,
                                      listen: false);
                                  final sp = Provider.of<ShopProvider>(context,
                                      listen: false);
                                  final ap = Provider.of<AuthProvider>(context,
                                      listen: false);
                                  await wp.refreshShops(authProvider: ap);
                                  if (mounted) sp.setShops(wp.shops);
                                });
                              }
                              return ShopPickerWidget(
                                selectedShopName: _selectedShopName,
                                controller: _shopFieldController,
                                onShopSelected: _onShopSelected,
                                onClear: _onShopCleared,
                              );
                            },
                          ),
                          // Сонгосон дэлгүүрийн мэдээлэл
                          ShopInfoWidget(
                            selectedShopName: _selectedShopName,
                            totalAmount: _totalAmount,
                          ),
                          const SizedBox(height: 12),
                          if (_selectedShopName == null) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.amber.shade400,
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.store_mall_directory_outlined,
                                    color: Colors.amber.shade900,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Дэлгүүр сонгоогүй байна. Дээрээс дэлгүүрээ сонгоно уу — үнэ, хөнгөлөлт зөв тооцогдоно.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.amber.shade900,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          const Text(
                            'Бараа нэмэх',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                                // Бараа хайх + Бараа сонгох
                                Container(
                                  key: _productSearchSectionKey,
                                  child: Consumer<ProductProvider>(
                                  builder: (context, productProvider, child) {
                                    // Гол дэлгэц дээр бичихэд доор нь саналын жагсаалт гаргахгүй.
                                    // Сонголт: «Бараа сонгох» эсвэл Enter → доод самбар.

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: productProvider
                                                  .products.isEmpty
                                              ? null
                                              : _openProductPicker,
                                          icon: const Icon(
                                              Icons.inventory_2_outlined,
                                              size: 20),
                                          label: const Text('Бараа сонгох'),
                                        ),
                                        const SizedBox(height: 12),

                                        // Show message if no products loaded
                                        if (_selectedShopName != null &&
                                            productProvider.products.isEmpty)
                                          Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.orange[50],
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color: Colors.orange[200]!),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(Icons.info_outline,
                                                    color: Colors.orange[700]),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    'Барааны мэдээлэл ачаалагдаагүй байна. Settings дээр очиж "Connect & Sync" товчийг дараарай.',
                                                    style: TextStyle(
                                                        color:
                                                            Colors.orange[900]),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    );
                                  },
                                ),
                                ),
                                const SizedBox(height: 8),
                                if (_currentProduct != null) ...[
                                  Builder(
                                    builder: (context) {
                                      final p = _currentProduct!;
                                      final upbRaw = (p.unitsPerBox ?? 1);
                                      final upb = upbRaw <= 0 ? 1 : upbRaw;
                                      final supportsBox = upb > 1;
                                      final unit = supportsBox
                                          ? (_productUnitModes[p.id] == 'box'
                                              ? 'box'
                                              : 'piece')
                                          : 'piece';

                                      return Container(
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          border: Border.all(
                                              color: Colors.grey.shade200),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Text(
                                              p.name,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF0F172A),
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    '1 хайрцагт: $upb',
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Text(
                                                    'Үлдэгдэл: ${p.stockQuantity ?? '-'}',
                                                    textAlign: TextAlign.right,
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 10),
                                            Builder(
                                              builder: (context) {
                                                final hasOnePlusOne =
                                                    _hasPromotion(p);
                                                final dp =
                                                    (p.discountPercent ?? 0);
                                                final hasDiscount = dp > 0;
                                                final hasPromo = hasOnePlusOne ||
                                                    hasDiscount;
                                                if (!hasPromo) {
                                                  return const SizedBox.shrink();
                                                }

                                                final checked =
                                                    _productUsePromotion[p.id] ==
                                                        true;

                                                String label() {
                                                  final bf = PromotionPricingUtils
                                                      .parseBuyFree(
                                                          p.promotionText);
                                                  final bulk = PromotionPricingUtils
                                                      .parseBulkDiscount(
                                                          p.promotionText);

                                                  final parts = <String>[];

                                                  // 1+1 / 1+2: "Хэд авбал хэд үнэгүй"
                                                  if (bf != null) {
                                                    parts.add(
                                                      '${bf.buy} ширхэг авбал ${bf.free} ширхэг үнэгүй',
                                                    );
                                                  }

                                                  // Bulk discount: "N ширхэг авбал -P%"
                                                  if (bulk != null) {
                                                    parts.add(
                                                      '${bulk.minQty} ширхэг авбал -${bulk.percent}%',
                                                    );
                                                  }

                                                  // Base discountPercent (fallback / always show if present)
                                                  if (hasDiscount) {
                                                    parts.add('-$dp%');
                                                  }

                                                  if (parts.isEmpty) {
                                                    return 'Урамшуулал/хямдрал ашиглах';
                                                  }
                                                  return 'Урамшуулал ашиглах (${parts.join(', ')})';
                                                }

                                                return CheckboxListTile(
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  value: checked,
                                                  onChanged: (v) {
                                                    setState(() {
                                                      _productUsePromotion[p.id] =
                                                          v ?? false;
                                                    });
                                                  },
                                                  title: Text(label()),
                                                  controlAffinity:
                                                      ListTileControlAffinity
                                                          .leading,
                                                );
                                              },
                                            ),
                                            const SizedBox(height: 6),
                                            if (supportsBox) ...[
                                              ToggleButtons(
                                                isSelected: [
                                                  unit == 'box',
                                                  unit == 'piece',
                                                ],
                                                onPressed: (i) {
                                                  final nextUnit =
                                                      i == 0 ? 'box' : 'piece';
                                                  if (nextUnit == unit) return;
                                                  setState(() {
                                                    _productUnitModes[p.id] =
                                                        nextUnit;
                                                    final curQty =
                                                        _productQuantities[
                                                                p.id] ??
                                                            1;
                                                    final nextQty =
                                                        nextUnit == 'box'
                                                            ? (curQty ~/ upb)
                                                                .clamp(1, 1 << 30)
                                                            : curQty.clamp(
                                                                1, 1 << 30);
                                                    _productQuantities[p.id] =
                                                        nextQty;
                                                    _addQtyController.text =
                                                        nextQty.toString();
                                                  });
                                                },
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                constraints:
                                                    const BoxConstraints(
                                                        minHeight: 36),
                                                children: const [
                                                  Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            horizontal: 10),
                                                    child: Text('Хайрцаг'),
                                                  ),
                                                  Padding(
                                                    padding:
                                                        EdgeInsets.symmetric(
                                                            horizontal: 10),
                                                    child: Text('Ширхэг'),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                            ],
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.center,
                                              children: [
                                                Expanded(
                                                  child: TextField(
                                                    controller:
                                                        _addQtyController,
                                                    keyboardType:
                                                        TextInputType.number,
                                                    decoration: InputDecoration(
                                                      labelText: unit == 'box'
                                                          ? 'Хайрцаг'
                                                          : 'Ширхэг',
                                                      border:
                                                          const OutlineInputBorder(),
                                                      isDense: true,
                                                    ),
                                                    onChanged: (v) {
                                                      final n =
                                                          int.tryParse(v) ?? 0;
                                                      _productQuantities[p.id] =
                                                          n < 1 ? 1 : n;
                                                      setState(() {});
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Builder(
                                                  builder: (context) {
                                                    final raw = _addQtyController
                                                        .text
                                                        .trim();
                                                    final n =
                                                        int.tryParse(raw) ?? 0;
                                                    final ordered =
                                                        n < 1 ? 1 : n;
                                                    final pieces = unit ==
                                                            'box'
                                                        ? ordered * upb
                                                        : ordered;
                                                    final applyPromo =
                                                        _productUsePromotion[
                                                                p.id] ==
                                                            true;
                                                    final previewMerged =
                                                        PromotionPricingUtils
                                                            .mergeCatalogPromotionText(
                                                      p.name,
                                                      p.promotionText,
                                                    );
                                                    final previewIdx =
                                                        _selectedItems
                                                            .indexWhere(
                                                      (it) =>
                                                          it.productId == p.id,
                                                    );
                                                    final previewMergedPhys =
                                                        previewIdx >= 0
                                                            ? _selectedItems[
                                                                        previewIdx]
                                                                    .quantity +
                                                                pieces
                                                            : pieces;
                                                    final tierPreview =
                                                        _cartWidePaidPiecesTotalWithProvisionalLine(
                                                      p: p,
                                                      mergedPromo:
                                                          previewMerged,
                                                      physicalPieces:
                                                          previewMergedPhys,
                                                      replaceIndex: previewIdx,
                                                      unitsPerBox: upb,
                                                    );
                                                    final d =
                                                        PromotionPricingUtils
                                                            .decide(
                                                      paidPieces: pieces,
                                                      baseUnitPrice:
                                                          _getProductPrice(p),
                                                      promotionText:
                                                          previewMerged,
                                                      baseDiscountPercent:
                                                          p.discountPercent,
                                                      apply: applyPromo,
                                                      catalogProductName:
                                                          p.name,
                                                      cartWidePaidPiecesTotal:
                                                          tierPreview,
                                                    );
                                                    final unitPrice =
                                                        d.unitPriceAfterDiscount;
                                                    final line =
                                                        unitPrice * pieces;
                                                    return Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment.end,
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        if (applyPromo &&
                                                            d.freePieces > 0)
                                                          Text(
                                                            'нийт ${d.totalPieces} ш (${d.paidPieces} төлөх + ${d.freePieces} үнэгүй)',
                                                            textAlign:
                                                                TextAlign.right,
                                                            style: TextStyle(
                                                              fontSize: 11,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: Colors
                                                                  .deepPurple
                                                                  .shade700,
                                                            ),
                                                          ),
                                                        Text(
                                                          '= ${line.toStringAsFixed(0)} ₮',
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 14,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            color: Color(
                                                                0xFF0D9488),
                                                          ),
                                                        ),
                                                      ],
                                                    );
                                                  },
                                                ),
                                                const SizedBox(width: 10),
                                                SizedBox(
                                                  height: 44,
                                                  child: ElevatedButton(
                                                    onPressed: _currentProduct ==
                                                            null
                                                        ? null
                                                        : () {
                                                            if (_selectedShopName ==
                                                                null) {
                                                              _showShopRequiredSnack();
                                                              return;
                                                            }
                                                            _addProductToCart();
                                                          },
                                                    style: ElevatedButton
                                                        .styleFrom(
                                                      backgroundColor:
                                                          Colors.blue,
                                                      foregroundColor:
                                                          Colors.white,
                                                    ),
                                                    child: const Text('НЭМЭХ'),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 10),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  unit == 'box'
                                                      ? '1 хайрцагийн үнэ:'
                                                      : '1 ширхэгийн үнэ:',
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Text(
                                                  '${_getProductDisplayPriceForUnit(p, unit).toStringAsFixed(0)} ₮',
                                                  style: const TextStyle(
                                                    fontSize: 15,
                                                    fontWeight: FontWeight.w800,
                                                    color: Color(0xFF0D9488),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                ] else ...[
                                  const SizedBox(height: 16),
                                ],
                          const SizedBox(height: 12),

                          // Сонгосон бараанууд
                          if (_selectedItems.isNotEmpty) ...[
                            Container(
                              key: _cartSectionKey,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFF0D9488)
                                      .withValues(alpha: 0.25),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Builder(
                                builder: (context) {
                                  final productProvider =
                                      Provider.of<ProductProvider>(context);
                                  final stockMap = <String, int>{};
                                  for (final p in productProvider.products) {
                                    final stock = p.stockQuantity;
                                    if (stock != null) stockMap[p.id] = stock;
                                  }
                                  return CartItemsWidget(
                                    items: _selectedItems,
                                    onRemoveItem: _removeProductFromCart,
                                    onItemChanged: _replaceCartItem,
                                    totalAmount: _totalAmount,
                                    lineSubtotalBeforeCartBulk: _cartLineSubtotal,
                                    cartBulkDiscountPercentIfUniform:
                                        _cartBulkUniformDiscountPercentForUi,
                                    stockByProductId:
                                        stockMap.isNotEmpty ? stockMap : null,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Notes
                          TextFormField(
                            controller: _notesController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Notes (Optional)',
                              hintText: 'Additional notes about the sale',
                              prefixIcon: Icon(Icons.note_outlined),
                              alignLabelWithHint: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 44,
                            child: ElevatedButton(
                              onPressed: _isLoading || _selectedItems.isEmpty
                                  ? null
                                  : () {
                                      if (_selectedShopName == null) {
                                        _showShopRequiredSnack();
                                        return;
                                      }
                                      if (_mode == _SalesEntryMode.orderOnly) {
                                        _showPaymentMethodDialogForOrderOnly();
                                      } else {
                                        _showPaymentMethodDialog();
                                      }
                                    },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                              ),
                              child: Text(
                                _isLoading
                                    ? 'Боловсруулж байна...'
                                    : 'ХАДГАЛАХ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 60),
                        ],
          ),
        ),
      ),
      ),
    );
  }
}

enum _SalesEntryMode { orderOnly, delivery }
