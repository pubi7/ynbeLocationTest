import 'package:dio/dio.dart';
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
import '../../models/sales_model.dart';
import '../../models/sales_item_model.dart';
import '../../models/product_model.dart';
import '../../widgets/hamburger_menu.dart';
import '../../widgets/bottom_navigation.dart';
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
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  final _productSearchController = TextEditingController();
  late final TextEditingController _shopFieldController;

  String? _selectedShopName;
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

      if (productProvider.products.isEmpty && mounted) {
        debugPrint('[SalesEntry] Products empty, refreshing from warehouse...');
        await warehouseProvider.refreshProducts();
        if (mounted) {
          productProvider.setProducts(warehouseProvider.products);
          debugPrint(
              '[SalesEntry] Loaded ${warehouseProvider.products.length} products');
        }
      } else {
        debugPrint(
            '[SalesEntry] Already have ${productProvider.products.length} products');
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
    _pageScrollController.dispose();
    _shopFieldController.dispose();
    _notesController.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  /// Дэлгүүр сонгосон үед тухайн дэлгүүрийн үнэ, эсвэл барааны үндсэн үнэ
  double _getProductPrice(Product product) {
    final shopProvider = Provider.of<ShopProvider>(context, listen: false);
    final shop = _selectedShopName != null
        ? shopProvider.getShopByName(_selectedShopName!)
        : null;
    return product.getPriceForCustomerType(shop?.customerTypeId);
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
      _shopFieldController.clear();
    });
  }

  double get _totalAmount {
    return _selectedItems.fold(0.0, (sum, item) => sum + item.total);
  }

  /// Note талбарт "10%" гэх мэт бичвэл order-level discount гэж үзээд хувиар буцаана.
  /// Жишээ: "10%" => 10.0
  double? _parsePercentFromNotes(String? notes) {
    final s = (notes ?? '').trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'(\d+(?:[.,]\d+)?)\s*%').firstMatch(s);
    if (m == null) return null;
    final raw = m.group(1)?.replaceAll(',', '.') ?? '';
    final v = double.tryParse(raw);
    if (v == null) return null;
    if (v <= 0) return null;
    return v.clamp(0, 100);
  }

  /// Баримт / eBarimt: НӨАТ орсон мөрүүдийн нийлбэр.
  double get _receiptGrossTotal {
    return _selectedItems.fold(0.0, (s, i) => s + i.receiptLineGross);
  }

  bool get _anyUnitPriceExcludesVat =>
      _selectedItems.any((i) => i.unitPriceExcludesVat);

  void _addProductToCart() {
    // Дэлгүүр сонгогдоогүй бол бараа нэмэхгүй
    if (_selectedShopName == null) {
      return;
    }

    if (_currentProduct == null) {
      return;
    }

    final p = _currentProduct!;
    const quantity = 1;
    final useOnePlusOne =
        _hasPromotion(p) && (_productUsePromotion[p.id] == true);

    int freePiecesForTotal(int total) {
      if (!useOnePlusOne || total <= 0) return 0;
      return total ~/ 2;
    }

    // Ижил бараа байвал тоог нэмэх
    final existingIndex = _selectedItems.indexWhere(
      (item) => item.productId == p.id,
    );

    if (existingIndex >= 0) {
      // Ижил бараа байвал тоог нэмэх
      final existingItem = _selectedItems[existingIndex];
      final newQty = existingItem.quantity + quantity;
      final newFree = freePiecesForTotal(newQty).clamp(0, newQty);
      _selectedItems[existingIndex] = SalesItem(
        productId: existingItem.productId,
        productName: existingItem.productName,
        price: existingItem.price,
        quantity: newQty,
        orderedUnit: existingItem.orderedUnit,
        orderedQuantity: existingItem.orderedQuantity + quantity,
        unitsPerBox: existingItem.unitsPerBox,
        freeQuantity: newFree,
        unitPriceExcludesVat: existingItem.unitPriceExcludesVat,
        discountPercent: p.discountPercent ?? existingItem.discountPercent,
        promotionText: (p.promotionText?.trim().isNotEmpty ?? false)
            ? p.promotionText
            : existingItem.promotionText,
      );
    } else {
      // Шинэ бараа нэмэх
      final newFree = freePiecesForTotal(quantity).clamp(0, quantity);
      _selectedItems.add(SalesItem(
        productId: p.id,
        productName: p.name,
        price: _getProductPrice(p),
        quantity: quantity,
        orderedUnit: 'piece',
        orderedQuantity: quantity,
        unitsPerBox: p.unitsPerBox ?? 1,
        freeQuantity: newFree,
        unitPriceExcludesVat: p.unitPriceExcludesVat,
        discountPercent: p.discountPercent,
        promotionText: p.promotionText,
      ));
    }

    setState(() {
      _currentProduct = null;
    });
  }

  void _removeProductFromCart(int index) {
    setState(() {
      _selectedItems.removeAt(index);
    });
  }

  void _updateCartItemQuantity(int index, String unit, int newQuantity) {
    setState(() {
      final item = _selectedItems[index];
      final upb = item.unitsPerBox <= 0 ? 1 : item.unitsPerBox;
      final supportsBox = upb > 1;

      int newPieces;
      int orderedQty;
      String orderedUnit;

      if (supportsBox) {
        final curBoxes = item.quantity ~/ upb;
        final curExtra = item.quantity % upb;
        final clampedBoxes = newQuantity < 0 ? 0 : newQuantity;
        final clampedExtra = newQuantity < 0 ? 0 : newQuantity;

        if (unit == 'box') {
          orderedQty = clampedBoxes;
          orderedUnit = 'box';
          newPieces = (orderedQty * upb) + curExtra;
        } else {
          final extra = clampedExtra.clamp(0, upb - 1);
          orderedQty = curBoxes;
          orderedUnit = 'box';
          newPieces = (orderedQty * upb) + extra;
        }
      } else {
        orderedUnit = unit;
        orderedQty = newQuantity < 0 ? 0 : newQuantity;
        newPieces = orderedUnit == 'box' ? (orderedQty * upb) : orderedQty;
      }

      if (newPieces <= 0) {
        // Do not allow zeroing out via edit; use delete instead.
        return;
      }
      final newFree = item.freeQuantity.clamp(0, newPieces);
      _selectedItems[index] = SalesItem(
        productId: item.productId,
        productName: item.productName,
        price: item.price,
        quantity: newPieces,
        orderedUnit: orderedUnit,
        orderedQuantity: orderedQty,
        unitsPerBox: upb,
        freeQuantity: newFree,
        unitPriceExcludesVat: item.unitPriceExcludesVat,
        discountPercent: item.discountPercent,
        promotionText: item.promotionText,
      );
    });
  }

  /// Check if promotion text contains 1+1 pattern
  bool _hasPromotion(Product product) {
    final promo = product.promotionText?.toLowerCase() ?? '';
    return promo.contains('1+1') ||
        promo.contains('1 + 1') ||
        promo.contains('нэг нэмэх нэг');
  }

  /// Show dialog asking if user wants to use promotion (1+1)
  Future<void> _askPromotionUsage(Product product) async {
    if (!_hasPromotion(product)) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.local_offer, color: Color(0xFF8B5CF6)),
            const SizedBox(width: 8),
            const Text('Урамшуулал'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product.name,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Урамшуулал: ${product.promotionText}',
              style: const TextStyle(fontSize: 14, color: Color(0xFF8B5CF6)),
            ),
            const SizedBox(height: 12),
            const Text('Энэ урамшууллыг ашиглах уу?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Үгүй'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
            ),
            child: const Text('Тийм'),
          ),
        ],
      ),
    );

    if (result != null) {
      setState(() {
        _productUsePromotion[product.id] = result;
      });
    }
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
    if (_selectedShopName == null) return;
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
        final scheduled = OrderScheduleUtils.computeDeliveryDateForWeb(role);
        final today = OrderScheduleUtils.yyyyMmDd(
          OrderScheduleUtils.dateOnly(DateTime.now(), useUtc: false),
        );
        String scheduledSuffix() {
          if (scheduled == null) return '';
          final t = OrderScheduleUtils.dateOnly(DateTime.now(), useUtc: false);
          final s = DateTime.tryParse(scheduled);
          if (s == null) return '';
          final sd = OrderScheduleUtils.dateOnly(s, useUtc: false);
          final diff = sd.difference(t).inDays;
          if (diff == 0) return '';
          final sign = diff > 0 ? '+' : '';
          return ' ($sign$diff)';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Захиалга үүсгэлээ (ID: ${pushed.orderId}).\nӨнөөдөр: $today\nХүргэлтийн өдөр${scheduledSuffix()}: ${scheduled ?? '-'}',
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
        if (mounted) {
          context.go('/sales-dashboard');
        }
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

  Future<void> _createOrderOnlyAndPush() async {
    if (_isLoading) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedShopName == null) return;
    if (_selectedItems.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final locationProvider =
          Provider.of<LocationProvider>(context, listen: false);
      final capturedLoc =
          await locationProvider.refreshLocationForOrderRecording();

      // Захиалга үүсгэх (баримт/хэвлэлгүй) — web site руу шууд илгээнэ.
      // Payment method-ийг backend талд ялгах зорилгоор "Sales" гэж тэмдэглэнэ.
      final pushed =
          await _pushOrderToWeve('Sales', applyDiscountFromNotes: false);
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
      final role = Provider.of<AuthProvider>(context, listen: false).userRole;
      final scheduled = OrderScheduleUtils.computeDeliveryDateForWeb(role);
      final today = OrderScheduleUtils.yyyyMmDd(
        OrderScheduleUtils.dateOnly(DateTime.now(), useUtc: false),
      );
      String scheduledSuffix() {
        if (scheduled == null) return '';
        final t = OrderScheduleUtils.dateOnly(DateTime.now(), useUtc: false);
        final s = DateTime.tryParse(scheduled);
        if (s == null) return '';
        final sd = OrderScheduleUtils.dateOnly(s, useUtc: false);
        final diff = sd.difference(t).inDays;
        if (diff == 0) return '';
        final sign = diff > 0 ? '+' : '';
        return ' ($sign$diff)';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ Захиалга үүсгэлээ (ID: ${pushed.orderId}).\nӨнөөдөр: $today\nХүргэлтийн өдөр${scheduledSuffix()}: ${scheduled ?? '-'}',
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
      if (mounted) {
        context.go('/sales-dashboard');
      }
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
    if (!_formKey.currentState!.validate()) return null;

    if (_selectedShopName == null) {
      return null;
    }

    if (_selectedItems.isEmpty) {
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

    // Амжилттай: бараа бүрийг тусдаа Sales record болгон нэмнэ
    for (var item in _selectedItems) {
      final sale = Sales(
        id: '${DateTime.now().millisecondsSinceEpoch}_${item.productId}',
        productName: item.productName,
        location: _selectedShopName!,
        salespersonId: authProvider.user?.id ?? '',
        salespersonName: authProvider.user?.name ?? '',
        amount: item.total,
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

    final items = _selectedItems.map((item) {
      final product = productProvider.getProductById(item.productId);
      final barcode = product?.barcode ?? product?.productCode ?? '';
      // qtyType: ширхгээр эсвэл кг-аар - одоогоор бүгдийг ширхэг
      final qtyType = (product?.netWeight != null && product!.netWeight! > 0)
          ? 'kg'
          : 'shirheg';
      return {
        'barcode': barcode.isNotEmpty ? barcode : item.productId,
        'name': item.productName,
        'unitPrice': item.receiptUnitGross,
        'qty': item.paidQuantity,
        'qtyType': qtyType,
        'totalAmount': item.receiptLineGross,
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

      // Find selected shop to get its ID
      final selectedShop = shopProvider.shops.firstWhere(
        (shop) => shop.name == _selectedShopName,
        orElse: () => shopProvider.shops.first,
      );

      // Parse customerId (backend expects int)
      final customerId = int.tryParse(selectedShop.id);
      if (customerId == null) {
        debugPrint('⚠️  Дэлгүүрийн ID буруу байна: ${selectedShop.id}');
        return null;
      }

      // Prepare order items with unitPrice for backend
      final notes = _notesController.text.trim();
      final notePercent =
          applyDiscountFromNotes ? _parsePercentFromNotes(notes) : null;
      final noteMultiplier =
          (notePercent != null) ? (1 - (notePercent / 100.0)) : 1.0;
      final items = _selectedItems.map((item) {
        final productId = int.tryParse(item.productId);
        if (productId == null) {
          throw Exception('Барааны ID буруу байна: ${item.productId}');
        }
        return {
          'productId': productId,
          'quantity': item.quantity,
          // Зөвхөн "шууд хэвлэх" үед note дээрх % хөнгөлөлтийг unitPrice-д шингээнэ.
          'unitPrice': (item.price * noteMultiplier),
        };
      }).toList();

      // Map payment method to backend format
      final backendPaymentMethod = _mapPaymentMethod(paymentMethod);

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      debugPrint('📤 Warehouse backend руу захиалга илгээж байна...');
      debugPrint('   • Нэвтэрсэн хэрэглэгч ID: ${authProvider.user?.id}');
      debugPrint('   • Нэвтэрсэн хэрэглэгч: ${authProvider.user?.name}');
      debugPrint('   • Дэлгүүр ID: $customerId');
      debugPrint('   • Барааны тоо: ${items.length}');
      debugPrint('   • Төлбөрийн төрөл: $backendPaymentMethod');

      // Сүүлчийн үлдэгдлийг татаж аваад (race condition-оос хамгаална) хүрэлцэхгүй бол илгээхгүй.
      try {
        await warehouseProvider.refreshProducts();
        if (mounted) {
          final productProvider =
              Provider.of<ProductProvider>(context, listen: false);
          productProvider.setProducts(warehouseProvider.products);
        }
      } catch (_) {}

      final productProvider =
          Provider.of<ProductProvider>(context, listen: false);
      for (final cart in _selectedItems) {
        final p = productProvider.getProductById(cart.productId);
        final stock = p?.stockQuantity ?? 0;
        if (stock > 0 && cart.quantity > stock) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Үлдэгдэл хүрэлцэхгүй: ${cart.productName} (үлдэгдэл $stock, хүссэн ${cart.quantity})',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return null;
        }
      }

      // Create order via warehouse backend API
      // Backend uses JWT token's userId as agentId (= mobile logged-in user's ID)
      final computedDeliveryDate =
          OrderScheduleUtils.computeDeliveryDateForWeb(authProvider.userRole);
      debugPrint(
          '🧩 createOrder role="${authProvider.userRole}" -> deliveryDate=$computedDeliveryDate');
      int? _retryAfterSeconds(DioException e) {
        final h = e.response?.headers;
        if (h == null) return null;
        final v = h.value('retry-after');
        if (v == null) return null;
        return int.tryParse(v.trim());
      }

      Future<Map<String, dynamic>> _createOrderWith429Retry() async {
        const maxAttempts = 3;
        for (var attempt = 1; attempt <= maxAttempts; attempt++) {
          try {
            return await warehouseProvider.createOrder(
              customerId: customerId,
              items: items,
              orderType: 'Store',
              paymentMethod: backendPaymentMethod,
              notes: notes.isEmpty ? null : notes,
              deliveryDate: computedDeliveryDate,
              allowInsufficientStock: false, // Үлдэгдэл хүрэлцэхгүй бол буцаана
            );
          } on DioException catch (e) {
            final status = e.response?.statusCode;
            if (status != 429 || attempt == maxAttempts) rethrow;

            final ra = _retryAfterSeconds(e);
            final backoff = ra ?? (attempt * 2); // 2s, 4s
            debugPrint(
                '⏳ 429 Too Many Requests. Retrying in ${backoff}s (attempt $attempt/$maxAttempts)');
            await Future.delayed(Duration(seconds: backoff));
          }
        }
        // Should not reach here
        throw Exception('Create order retry loop failed unexpectedly');
      }

      final result = await _createOrderWith429Retry();

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
      rethrow;
    }
  }

  /// Map mobile app payment method to backend format
  String _mapPaymentMethod(String mobileMethod) {
    switch (mobileMethod.toLowerCase()) {
      case 'cash':
      case 'бэлэн':
        return 'Cash';
      case 'credit':
      case 'зээл':
        return 'Credit';
      case 'bank':
      case 'банк':
        return 'BankTransfer';
      case 'sales':
      case 'борлуулалт':
        return 'Sales';
      case 'padan':
      case 'падан':
        return 'Padan';
      default:
        return 'Cash';
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
          setState(() => _mode = _SalesEntryMode.orderOnly);
          return;
        }
        if (isManagerRole(authRole)) {
          setState(() => _mode = _SalesEntryMode.orderOnly);
          return;
        }
        final picked = await _askEntryMode();
        if (!mounted) return;
        setState(() {
          _mode = picked ?? _SalesEntryMode.delivery;
        });
      });
    }

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(
          switch (_mode) {
            _SalesEntryMode.orderOnly => 'Хүргэлт (захиалга) үүсгэх',
            _SalesEntryMode.delivery => 'Газар дээр (хэвлэх)',
            _ => 'Sales',
          },
        ),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.go('/sales-dashboard'),
          ),
        ],
      ),
      drawer: const HamburgerMenu(),
      bottomNavigationBar: const BottomNavigationWidget(),
      body: Stack(
        children: [
          SingleChildScrollView(
            controller: _pageScrollController,
            padding:
                EdgeInsets.only(bottom: _selectedItems.isNotEmpty ? 100 : 0),
            child: Column(
              children: [
                // Header Section - Refined gradient with depth
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF0D9488),
                        const Color(0xFF0F766E),
                        const Color(0xFF115E59),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0D9488).withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.receipt_long_rounded,
                              size: 44,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Захиалга үүсгэх',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Дэлгүүр сонгоод бараа нэмнэ үү',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Form Section
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0xFF0D9488).withValues(alpha: 0.12),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF0D9488).withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
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
                          const SizedBox(height: 20),

                          // Бараа нэмэх хэсэг
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  const Color(0xFFF0FDFA),
                                  const Color(0xFFF8FAFC),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFF0D9488)
                                    .withValues(alpha: 0.2),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF0D9488)
                                      .withValues(alpha: 0.06),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0D9488)
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.add_shopping_cart_rounded,
                                        size: 20,
                                        color: Color(0xFF0D9488),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            'Бараа нэмэх',
                                            style: TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.w700,
                                              color: const Color(0xFF1F2937),
                                              letterSpacing: -0.3,
                                            ),
                                          ),
                                          if (_selectedShopName == null)
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 4,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.amber
                                                    .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                'Дэлгүүр сонгоно уу',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.amber.shade800,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // Бараа хайх + Бараа сонгох
                                Container(
                                  key: _productSearchSectionKey,
                                  child: Consumer<ProductProvider>(
                                  builder: (context, productProvider, child) {
                                    // Үнэтэй бараанууд л харуулна; хайлтаар шүүнэ
                                    final searchText = _productSearchController
                                        .text
                                        .toLowerCase();
                                    final filteredProducts = (searchText.isEmpty
                                            ? const <Product>[]
                                            : productProvider.products.where(
                                                (p) {
                                                  final name =
                                                      p.name.trim().toLowerCase();
                                                  if (name.isEmpty) {
                                                    // Requirement: only show products with a written name.
                                                    return false;
                                                  }
                                                  return name.contains(searchText) ||
                                                      (p.barcode ?? '')
                                                          .toLowerCase()
                                                          .contains(searchText) ||
                                                      (p.productCode ?? '')
                                                          .toLowerCase()
                                                          .contains(searchText);
                                                },
                                              ))
                                        // Дэлгүүр сонгоогүй үед ч жагсаалтаар харуулах хэрэгтэй.
                                        // Үнэ нь зөвхөн дэлгүүрээс хамаарч 0 байж болох тул энэ үед шүүхгүй.
                                        .where((p) => _selectedShopName == null
                                            ? true
                                            : _getProductPrice(p) > 0)
                                        .toList();

                                    // Search bar
                                    final searchBar = Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: const Color(0xFF0D9488)
                                              .withValues(alpha: 0.25),
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF0D9488)
                                                .withValues(alpha: 0.06),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: TextField(
                                        controller: _productSearchController,
                                        enabled:
                                            productProvider.products.isNotEmpty,
                                        onTap: () {
                                          setState(() {});
                                        },
                                        decoration: InputDecoration(
                                          labelText: 'Бараа хайх',
                                          hintText: _selectedShopName == null
                                              ? 'Дэлгүүр сонговол үнэ/хөнгөлөлт зөв болно'
                                              : (productProvider
                                                      .products.isEmpty
                                                  ? 'Бараа алга'
                                                  : 'Барааны нэр / баркод / SKU'),
                                          labelStyle: const TextStyle(
                                            color: Color(0xFF0F172A),
                                            fontWeight: FontWeight.w600,
                                          ),
                                          hintStyle: TextStyle(
                                            color: Colors.grey[600],
                                          ),
                                          prefixIcon: const Icon(
                                            Icons.search_rounded,
                                            size: 22,
                                            color: Color(0xFF0D9488),
                                          ),
                                          suffixIcon: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (_productSearchController
                                                  .text.isNotEmpty)
                                                IconButton(
                                                  icon: const Icon(Icons.clear,
                                                      size: 20),
                                                  onPressed: () {
                                                    setState(() {
                                                      _productSearchController
                                                          .clear();
                                                    });
                                                  },
                                                ),
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.qr_code_scanner,
                                                    size: 24,
                                                    color: Color(0xFF6366F1)),
                                                tooltip: 'Баркод уншуулах',
                                                onPressed: () {
                                                  // TODO: Implement barcode scanner
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                    const SnackBar(
                                                      content: Text(
                                                          'Баркод уншуулах функц хөгжүүлэгдэж байна...'),
                                                      duration:
                                                          Duration(seconds: 2),
                                                    ),
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                          filled: true,
                                          fillColor: Colors.white,
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide.none,
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide.none,
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: const BorderSide(
                                                color: Color(0xFF6366F1),
                                                width: 2),
                                          ),
                                        ),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: Color(0xFF0F172A),
                                        ),
                                        cursorColor: Color(0xFF0D9488),
                                        onChanged: (value) {
                                          setState(() {}); // Rebuild to filter
                                        },
                                      ),
                                    );

                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        searchBar,
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

                                        // Show message if search returns no results
                                        if (_selectedShopName != null &&
                                            productProvider
                                                .products.isNotEmpty &&
                                            _productSearchController
                                                .text.isNotEmpty &&
                                            filteredProducts.isEmpty)
                                          Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[100],
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color: Colors.grey[300]!),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(Icons.search_off,
                                                    color: Colors.grey[600]),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    '"${_productSearchController.text}" гэсэн бараа олдсонгүй',
                                                    style: TextStyle(
                                                        color:
                                                            Colors.grey[800]),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),

                                        // Хайлт хоосон үед барааны мэдээлэл харагдахгүй (requirement).
                                        if (_productSearchController
                                            .text
                                            .trim()
                                            .isEmpty)
                                          Container(
                                            padding: const EdgeInsets.all(14),
                                            decoration: BoxDecoration(
                                              color: Colors.grey[100],
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color: Colors.grey[300]!),
                                            ),
                                            child: Row(
                                              children: [
                                                Icon(Icons.search_rounded,
                                                    color: Colors.grey[700]),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    'Бараа хайхын тулд дээрээс нэр/баркод/SKU бичнэ үү.',
                                                    style: TextStyle(
                                                        color:
                                                            Colors.grey[800]),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          )
                                        else if (filteredProducts.isNotEmpty)
                                          Container(
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                color: const Color(0xFF0D9488)
                                                    .withValues(alpha: 0.25),
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.05),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 3),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              children: [
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.fromLTRB(
                                                          12, 10, 12, 6),
                                                  child: Row(
                                                    children: [
                                                      const Icon(
                                                        Icons
                                                            .touch_app_rounded,
                                                        size: 18,
                                                        color:
                                                            Color(0xFF0D9488),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Text(
                                                          'Дээрээс нь дараад шууд нэмнэ (2 ширхэгээр харуулна)',
                                                          style: TextStyle(
                                                            color: Colors
                                                                .grey[700],
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 12,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const Divider(height: 1),
                                                ListView.builder(
                                                  shrinkWrap: true,
                                                  physics:
                                                      const NeverScrollableScrollPhysics(),
                                                  itemCount:
                                                      filteredProducts.length >
                                                              2
                                                          ? 2
                                                          : filteredProducts
                                                              .length,
                                                  itemBuilder:
                                                      (context, index) {
                                                    final product =
                                                        filteredProducts[index];
                                                    final price =
                                                        _getProductPrice(
                                                            product);
                                                    final stock =
                                                        product.stockQuantity;

                                                    return ListTile(
                                                      dense: true,
                                                      contentPadding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                              horizontal: 12,
                                                              vertical: 2),
                                                      title: Text(
                                                        product.name,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                      subtitle: Text(
                                                        [
                                                          if (price > 0)
                                                            '${price.toStringAsFixed(0)} ₮',
                                                          if (stock != null)
                                                            'Үлдэгдэл: $stock',
                                                          if ((product.barcode ??
                                                                  '')
                                                              .trim()
                                                              .isNotEmpty)
                                                            'Barcode: ${product.barcode}',
                                                        ].join(' • '),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      trailing: const Icon(
                                                        Icons
                                                            .add_circle_outline_rounded,
                                                        color:
                                                            Color(0xFF0D9488),
                                                      ),
                                                      onTap: () async {
                                                        if (_selectedShopName ==
                                                            null) {
                                                          if (!mounted) return;
                                                          ScaffoldMessenger.of(
                                                                  context)
                                                              .showSnackBar(
                                                            const SnackBar(
                                                              content: Text(
                                                                  'Эхлээд дэлгүүр сонгоно уу'),
                                                              backgroundColor:
                                                                  Colors.orange,
                                                              duration: Duration(
                                                                  seconds: 3),
                                                            ),
                                                          );
                                                          return;
                                                        }
                                                        if (_hasPromotion(
                                                            product)) {
                                                          await _askPromotionUsage(
                                                              product);
                                                        }
                                                        setState(() {
                                                          _currentProduct =
                                                              product;
                                                        });
                                                        _addProductToCart();
                                                        setState(() {
                                                          _productSearchController
                                                              .clear();
                                                        });
                                                      },
                                                    );
                                                  },
                                                ),
                                                if (filteredProducts.length > 2)
                                                  Padding(
                                                    padding:
                                                        const EdgeInsets.fromLTRB(
                                                            12, 8, 12, 10),
                                                    child: Text(
                                                      '+${filteredProducts.length - 2} бараа байна. Илүү нарийвчилж хайгаарай.',
                                                      style: TextStyle(
                                                        color: Colors.grey[600],
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          )
                                        else
                                          const SizedBox.shrink(),
                                      ],
                                    );
                                  },
                                ),
                                ),
                                const SizedBox(height: 16),
                                // Барааны үнэ
                                if (_currentProduct != null)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: Colors.grey.shade200),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            const Text(
                                              'Үнэ:',
                                              style: TextStyle(fontSize: 14),
                                            ),
                                            Text(
                                              '${_getProductPrice(_currentProduct!).toStringAsFixed(0)} ₮',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF0D9488),
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (_currentProduct!
                                            .unitPriceExcludesVat) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'НӨАТ ороогүй үнэ',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[700],
                                            ),
                                          ),
                                        ],
                                        const SizedBox(height: 8),
                                        if ((_currentProduct!.barcode ?? '')
                                            .isNotEmpty)
                                          Text(
                                            'Barcode: ${_currentProduct!.barcode}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[700]),
                                          ),
                                        if (_currentProduct!.stockQuantity !=
                                            null)
                                          Text(
                                            'Үлдэгдэл: ${_currentProduct!.stockQuantity} ширхэг',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[700]),
                                          ),
                                        if (_currentProduct!.unitsPerBox !=
                                            null)
                                          Text(
                                            'Хайрцаг дахь тоо: ${_currentProduct!.unitsPerBox}',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[700]),
                                          ),
                                      ],
                                    ),
                                  ),
                                if (_currentProduct != null)
                                  const SizedBox(height: 16),
                                // Нэмэх товч - ТОМ, ТОД
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton.icon(
                                    onPressed: (_selectedShopName == null ||
                                            _currentProduct == null)
                                        ? null
                                        : () {
                                            _addProductToCart();
                                          },
                                    icon:
                                        const Icon(Icons.add_circle, size: 24),
                                    label: const Text(
                                      'Сагсанд нэмэх ➕',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0D9488),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      elevation: 3,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Hint text
                                if (_selectedItems.isEmpty)
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0F9FF),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: const Color(0xFF3B82F6)),
                                    ),
                                    child: const Row(
                                      children: [
                                        Icon(Icons.info_outline,
                                            color: Color(0xFF3B82F6), size: 20),
                                        SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Олон бараа нэмж болно! Бараа бүрийг "Сагсанд нэмэх" дарж нэмнэ үү.',
                                            style: TextStyle(
                                              color: Color(0xFF1E40AF),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Сонгосон бараанууд (шууд засварлана)
                          if (_selectedItems.isNotEmpty) ...[
                            Container(
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
                                    onQuantityChanged: (i, unit, value) {
                                      _updateCartItemQuantity(i, unit, value);
                                    },
                                    totalAmount: _totalAmount,
                                    stockByProductId:
                                        stockMap.isNotEmpty ? stockMap : null,
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 20),
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
                          const SizedBox(height: 100), // Space for bottom bar
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Sticky Bottom Action Bar
          if (_selectedItems.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Нийт дүн',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_totalAmount.toStringAsFixed(0)} ₮',
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF6366F1),
                              ),
                            ),
                            if (_anyUnitPriceExcludesVat) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Баримт (НӨАТ орсон): ${_receiptGrossTotal.toStringAsFixed(0)} ₮',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 56,
                          child: ElevatedButton.icon(
                            onPressed: (_isLoading ||
                                    _selectedItems.isEmpty ||
                                    _selectedShopName == null)
                                ? null
                                : (_mode == _SalesEntryMode.orderOnly
                                    ? _createOrderOnlyAndPush
                                    : _showPaymentMethodDialog),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6366F1),
                              foregroundColor: Colors.white,
                              elevation: 4,
                              shadowColor:
                                  const Color(0xFF6366F1).withOpacity(0.4),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.check_circle, size: 24),
                            label: Text(
                              _isLoading
                                  ? 'Боловсруулж байна...'
                                  : (_mode == _SalesEntryMode.orderOnly
                                      ? 'Захиалга (хүргэлт) үүсгээд илгээх'
                                      : 'Хэвлээд дуусгах'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _SalesEntryMode { orderOnly, delivery }
