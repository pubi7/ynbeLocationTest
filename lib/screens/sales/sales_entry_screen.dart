import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/sales_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/shop_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../models/sales_model.dart';
import '../../models/sales_item_model.dart';
import '../../models/product_model.dart';
import '../../widgets/hamburger_menu.dart';
import '../../widgets/bottom_navigation.dart';
import '../../widgets/sales_entry/shop_picker_widget.dart';
import '../../widgets/sales_entry/shop_info_widget.dart';
import '../../widgets/sales_entry/cart_items_widget.dart';
import '../../widgets/sales_entry/payment_method_dialog.dart';
import '../../services/receipt_service.dart';

class SalesEntryScreen extends StatefulWidget {
  const SalesEntryScreen({super.key});

  @override
  State<SalesEntryScreen> createState() => _SalesEntryScreenState();
}

class _SalesEntryScreenState extends State<SalesEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  final _productSearchController = TextEditingController();
  late final TextEditingController _shopFieldController;

  String? _selectedShopName;
  bool _showProductList = false; // Control product list visibility

  // Олон бараа сонгох
  List<SalesItem> _selectedItems = [];
  Set<String> _selectedProductIds = {}; // For multi-select
  Product? _currentProduct;
  final _currentQuantityController = TextEditingController();
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

  @override
  void dispose() {
    _shopFieldController.dispose();
    _currentQuantityController.dispose();
    _notesController.dispose();
    _productSearchController.dispose();
    super.dispose();
  }

  void _onShopSelected(String shopName) {
    setState(() {
      _selectedShopName = shopName;
      _shopFieldController.text = shopName;
    });
    _checkShopCreditStatus(shopName);
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

  void _addProductToCart() {
    // Дэлгүүр сонгогдоогүй бол бараа нэмэхгүй
    if (_selectedShopName == null) {
      return;
    }

    if (_currentProduct == null || _currentQuantityController.text.isEmpty) {
      return;
    }

    final quantity = int.tryParse(_currentQuantityController.text) ?? 0;
    if (quantity <= 0) {
      return;
    }

    // Ижил бараа байвал тоог нэмэх
    final existingIndex = _selectedItems.indexWhere(
      (item) => item.productId == _currentProduct!.id,
    );

    if (existingIndex >= 0) {
      // Ижил бараа байвал тоог нэмэх
      final existingItem = _selectedItems[existingIndex];
      _selectedItems[existingIndex] = SalesItem(
        productId: existingItem.productId,
        productName: existingItem.productName,
        price: existingItem.price,
        quantity: existingItem.quantity + quantity,
      );
    } else {
      // Шинэ бараа нэмэх
      _selectedItems.add(SalesItem(
        productId: _currentProduct!.id,
        productName: _currentProduct!.name,
        price: _currentProduct!.price,
        quantity: quantity,
      ));
    }

    setState(() {
      _currentProduct = null;
      _currentQuantityController.clear();
    });
  }

  // Add all selected products using entered quantity/discount
  void _addAllSelectedProductsToCart() {
    if (_selectedShopName == null || _selectedProductIds.isEmpty) {
      return;
    }

    final productProvider =
        Provider.of<ProductProvider>(context, listen: false);

    for (final productId in _selectedProductIds) {
      final product = productProvider.getProductById(productId);
      if (product == null) continue;

      final enteredQty = _productQuantities[productId] ?? 1;
      final unitMode = _productUnitModes[productId] ?? 'piece';
      final unitsPerBox = product.unitsPerBox ?? 1;
      final quantity =
          unitMode == 'box' ? (enteredQty * unitsPerBox) : enteredQty;
      final discountPercent = (product.discountPercent ?? 0).clamp(0, 100);
      final effectivePrice =
          product.price * (1 - (discountPercent.toDouble() / 100));

      // Apply 1+1 promotion if user chose to use it
      final usePromotion = _productUsePromotion[productId] ?? false;
      int finalQuantity = quantity;
      double finalPrice = effectivePrice;

      if (usePromotion && _hasPromotion(product)) {
        // 1+1: buy 1 get 1 free
        // If quantity is even: pay for half (e.g., buy 4 = pay for 2, get 4)
        // If quantity is odd: pay for (quantity+1)/2 (e.g., buy 3 = pay for 2, get 3)
        final payQuantity = (quantity + 1) ~/ 2; // Round up division
        finalQuantity = quantity; // Total quantity received
        // Price per unit stays same, but we only charge for payQuantity
        // So we adjust the price: effectivePrice * (payQuantity / quantity)
        finalPrice = effectivePrice * (payQuantity / quantity);
      }

      // Check if product already in cart
      final existingIndex = _selectedItems.indexWhere(
        (item) => item.productId == productId,
      );

      if (existingIndex >= 0) {
        // Add to existing quantity
        final existingItem = _selectedItems[existingIndex];
        // If promotion was used, recalculate
        final existingQty = existingItem.quantity;
        final newTotalQty = existingQty + finalQuantity;
        final newPayQty = usePromotion && _hasPromotion(product)
            ? ((existingQty + 1) ~/ 2) + ((finalQuantity + 1) ~/ 2)
            : newTotalQty;
        final newPrice = usePromotion && _hasPromotion(product)
            ? effectivePrice * (newPayQty / newTotalQty)
            : effectivePrice;

        _selectedItems[existingIndex] = SalesItem(
          productId: existingItem.productId,
          productName: existingItem.productName,
          price: newPrice,
          quantity: newTotalQty,
        );
      } else {
        // Add new item
        _selectedItems.add(SalesItem(
          productId: product.id,
          productName: product.name,
          price: finalPrice,
          quantity: finalQuantity,
        ));
      }
    }

    setState(() {
      _selectedProductIds.clear();
      _productQuantities.clear();
      _productUnitModes.clear();
      _productUsePromotion.clear();
      _showProductList = false; // Hide product list after adding
      _productSearchController.clear(); // Clear search
    });
  }

  void _removeProductFromCart(int index) {
    setState(() {
      _selectedItems.removeAt(index);
    });
  }

  void _updateCartItemQuantity(int index, int newQuantity) {
    setState(() {
      final item = _selectedItems[index];
      _selectedItems[index] = SalesItem(
        productId: item.productId,
        productName: item.productName,
        price: item.price,
        quantity: newQuantity,
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
    setState(() {
      _isLoading = true;
    });

    try {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);

      // Баримт хэвлэх
      await ReceiptService.printReceipt(
        items: _selectedItems,
        shopName: _selectedShopName ?? 'Дэлгүүр',
        paymentMethod: paymentMethod,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        salesperson: authProvider.user,
      );

      // ebarimt руу мэдээлэл илгээх
      await _sendToEbarimt(paymentMethod);

      // Sales бүртгэх (paymentMethod-тэй)
      await _submitSaleWithPaymentMethod(paymentMethod);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('✅ $paymentMethod төлбөрөөр худалдан авалт амжилттай!'),
                const SizedBox(height: 4),
                const Text(
                  '🌐 Захиалга Weve сайт дээр харагдаж байна',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
        context.go('/sales-dashboard');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Алдаа гарлаа: $e'),
            backgroundColor: Colors.red,
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

  void _showAddProductDialog() {
    final nameController = TextEditingController();
    final priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Шинэ бараа нэмэх'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Барааны нэр *'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Үнэ (₮) *'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Цуцлах'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final price = double.tryParse(priceController.text.trim());
              if (name.isEmpty || price == null || price <= 0) return;

              final productProvider =
                  Provider.of<ProductProvider>(context, listen: false);
              final id = DateTime.now().millisecondsSinceEpoch.toString();
              final product = Product(id: id, name: name, price: price);
              productProvider.addProduct(product);

              setState(() {
                _currentProduct = product;
              });

              Navigator.pop(ctx);
            },
            child: const Text('Нэмэх'),
          ),
        ],
      ),
    ).then((_) {
      nameController.dispose();
      priceController.dispose();
    });
  }

  Future<void> _submitSaleWithPaymentMethod(String paymentMethod) async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedShopName == null) {
      return;
    }

    if (_selectedItems.isEmpty) {
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final salesProvider = Provider.of<SalesProvider>(context, listen: false);
    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);

    // Одоогийн GPS байршлыг авах
    double? latitude;
    double? longitude;
    if (locationProvider.currentLocation != null) {
      latitude = locationProvider.currentLocation!.latitude;
      longitude = locationProvider.currentLocation!.longitude;
    }

    // Одоогийн IP хаягийг авах
    final ipAddress = locationProvider.currentIpAddress;

    // Олон барааны хувьд бүр бараа бүрийг тусдаа Sales record болгон бүртгэх
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
      );

      await salesProvider.addSale(sale);
    }

    // Push order to Weve site (mock for now)
    await _pushOrderToWeve(paymentMethod);

    // Read-only mode: do NOT send sales/orders to Warehouse web backend.
  }

  Future<void> _sendToEbarimt(String paymentMethod) async {
    // ebarimt.mn API руу мэдээлэл илгээх
    // Одоогоор mock функц - бодит API-д солих хэрэгтэй

    final locationName = _selectedShopName ?? 'Дэлгүүр';

    // Mock API call
    await Future.delayed(const Duration(seconds: 1));

    print('Ebarimt руу илгээж байна:');
    print('Байршил: $locationName');
    print('Төлбөрийн төрөл: $paymentMethod');
    print('Барааны тоо: ${_selectedItems.length}');
    for (var item in _selectedItems) {
      print(
          '  - ${item.productName}: ${item.quantity} x ${item.price.toStringAsFixed(0)} ₮ = ${item.total.toStringAsFixed(0)} ₮');
    }
    print('Нийт үнэ: ${_totalAmount.toStringAsFixed(0)} ₮');

    // Бодит API call жишээ:
    // final response = await http.post(
    //   Uri.parse('https://api.ebarimt.mn/receipt'),
    //   headers: {'Content-Type': 'application/json'},
    //   body: jsonEncode({
    //     'location': locationName,
    //     'paymentMethod': paymentMethod,
    //     'items': _selectedItems.map((item) => item.toJson()).toList(),
    //     'totalAmount': _totalAmount,
    //   }),
    // );
  }

  Future<void> _pushOrderToWeve(String paymentMethod) async {
    try {
      final warehouseProvider =
          Provider.of<WarehouseProvider>(context, listen: false);
      final shopProvider = Provider.of<ShopProvider>(context, listen: false);

      if (!warehouseProvider.connected) {
        debugPrint('⚠️  Warehouse backend-тэй холбогдоогүй байна');
        return;
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
        return;
      }

      // Prepare order items (backend expects: [{ productId: int, quantity: int }])
      final items = _selectedItems.map((item) {
        final productId = int.tryParse(item.productId);
        if (productId == null) {
          throw Exception('Барааны ID буруу байна: ${item.productId}');
        }
        return {
          'productId': productId,
          'quantity': item.quantity,
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

      // Create order via warehouse backend API
      // Backend uses JWT token's userId as agentId (= mobile logged-in user's ID)
      final result = await warehouseProvider.createOrder(
        customerId: customerId,
        items: items,
        orderType: 'Store',
        paymentMethod: backendPaymentMethod,
      );

      debugPrint('✅ Захиалга амжилттай илгээгдлээ!');
      debugPrint('   • Order ID: ${result['order']?['id']}');
      debugPrint('   • Agent ID (backend): ${result['order']?['agentId']}');
      debugPrint('   • Order Number: ${result['order']?['orderNumber']}');
      debugPrint('🌐 Захиалга web dashboard дээр харагдаж байна!');
    } catch (e) {
      debugPrint('❌ Захиалга илгээхэд алдаа гарлаа: $e');
      // Don't show error to user - this is secondary functionality
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Record Sale'),
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
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
            padding:
                EdgeInsets.only(bottom: _selectedItems.isNotEmpty ? 100 : 0),
            child: Column(
              children: [
                // Header Section with Gradient
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF10B981),
                        Color(0xFF059669),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.sell_rounded,
                            size: 48,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Record New Sale',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Enter the details of the product sold',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),

                // Form Section
                Container(
                  margin: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
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
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    const Text(
                                      'Бараа нэмэх',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (_selectedShopName == null) ...[
                                      const SizedBox(width: 8),
                                      const Text(
                                        '(Дэлгүүр сонгоно уу)',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.orange,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 16),
                                // Бараа хайх + Бараа сонгох (+ Шинэ бараа)
                                Consumer<ProductProvider>(
                                  builder: (context, productProvider, child) {
                                    // Үнэтэй бараанууд л харуулна; хайлтаар шүүнэ
                                    final searchText = _productSearchController
                                        .text
                                        .toLowerCase();
                                    final filteredProducts = (searchText.isEmpty
                                            ? productProvider.products
                                            : productProvider.products
                                                .where((p) {
                                                return p.name
                                                        .toLowerCase()
                                                        .contains(searchText) ||
                                                    (p.barcode ?? '')
                                                        .toLowerCase()
                                                        .contains(searchText) ||
                                                    (p.productCode ?? '')
                                                        .toLowerCase()
                                                        .contains(searchText);
                                              }))
                                        .where((p) => p.price > 0)
                                        .toList();

                                    // Search bar
                                    final searchBar = Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                            color: Colors.grey[300]!, width: 1),
                                      ),
                                      child: TextField(
                                        controller: _productSearchController,
                                        enabled: _selectedShopName != null &&
                                            productProvider.products.isNotEmpty,
                                        onTap: () {
                                          // Show product list when tapped
                                          setState(() {
                                            _showProductList = true;
                                          });
                                        },
                                        decoration: InputDecoration(
                                          labelText: '🔍 Бараа хайх',
                                          hintText: _selectedShopName == null
                                              ? 'Эхлээд дэлгүүр сонгоно уу'
                                              : (productProvider
                                                      .products.isEmpty
                                                  ? 'Бараа алга'
                                                  : 'Барааны нэр / баркод / SKU'),
                                          prefixIcon: const Icon(Icons.search,
                                              size: 24,
                                              color: Color(0xFF6366F1)),
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
                                        style: const TextStyle(fontSize: 16),
                                        onChanged: (value) {
                                          setState(() {
                                            // Auto-show product list when user types
                                            if (value.isNotEmpty) {
                                              _showProductList = true;
                                            }
                                          }); // Rebuild to filter
                                        },
                                      ),
                                    );

                                    final addBtn = ElevatedButton.icon(
                                      onPressed: _selectedShopName == null
                                          ? null
                                          : _showAddProductDialog,
                                      icon: const Icon(Icons.add_rounded),
                                      label: const Text('Шинэ'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF10B981),
                                        foregroundColor: Colors.white,
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

                                        // Checkbox list with quantities - Show when typing or tapped
                                        if (_showProductList &&
                                            filteredProducts.isNotEmpty &&
                                            _selectedShopName != null)
                                          Container(
                                            height: 350,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color:
                                                      const Color(0xFF10B981),
                                                  width: 2),
                                            ),
                                            child: Column(
                                              children: [
                                                // Header
                                                Container(
                                                  padding:
                                                      const EdgeInsets.all(12),
                                                  decoration:
                                                      const BoxDecoration(
                                                    color: Color(0xFF10B981),
                                                    borderRadius:
                                                        BorderRadius.only(
                                                      topLeft:
                                                          Radius.circular(10),
                                                      topRight:
                                                          Radius.circular(10),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .spaceBetween,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          const Icon(
                                                              Icons
                                                                  .check_circle,
                                                              color:
                                                                  Colors.white,
                                                              size: 20),
                                                          const SizedBox(
                                                              width: 8),
                                                          Text(
                                                            '✓ ${_selectedProductIds.length} бараа сонгосон',
                                                            style:
                                                                const TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .bold,
                                                              fontSize: 16,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      if (_selectedProductIds
                                                          .isNotEmpty)
                                                        TextButton(
                                                          onPressed: () {
                                                            setState(() {
                                                              _selectedProductIds
                                                                  .clear();
                                                              _productQuantities
                                                                  .clear();
                                                              _productUnitModes
                                                                  .clear();
                                                              _productUsePromotion
                                                                  .clear();
                                                            });
                                                          },
                                                          style: TextButton
                                                              .styleFrom(
                                                            padding:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        8,
                                                                    vertical:
                                                                        4),
                                                          ),
                                                          child: const Text(
                                                            'Цэвэрлэх',
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold),
                                                          ),
                                                        ),
                                                    ],
                                                  ),
                                                ),
                                                // Product list
                                                Expanded(
                                                  child: ListView.builder(
                                                    itemCount:
                                                        filteredProducts.length,
                                                    itemBuilder:
                                                        (context, index) {
                                                      final product =
                                                          filteredProducts[
                                                              index];
                                                      final isSelected =
                                                          _selectedProductIds
                                                              .contains(
                                                                  product.id);
                                                      final quantity =
                                                          _productQuantities[
                                                                  product.id] ??
                                                              1;
                                                      final unitMode =
                                                          _productUnitModes[
                                                                  product.id] ??
                                                              'piece';
                                                      final unitsPerBox =
                                                          product.unitsPerBox ??
                                                              1;

                                                      return Material(
                                                        color:
                                                            Colors.transparent,
                                                        child: InkWell(
                                                          onTap: () async {
                                                            if (isSelected) {
                                                              setState(() {
                                                                _selectedProductIds
                                                                    .remove(
                                                                        product
                                                                            .id);
                                                                _productQuantities
                                                                    .remove(
                                                                        product
                                                                            .id);
                                                                _productUnitModes
                                                                    .remove(
                                                                        product
                                                                            .id);
                                                                _productUsePromotion
                                                                    .remove(
                                                                        product
                                                                            .id);
                                                              });
                                                            } else {
                                                              if (_hasPromotion(
                                                                  product)) {
                                                                await _askPromotionUsage(
                                                                    product);
                                                              }
                                                              setState(() {
                                                                _selectedProductIds
                                                                    .add(product
                                                                        .id);
                                                                _productQuantities[
                                                                    product
                                                                        .id] = 1;
                                                                _productUnitModes[
                                                                        product
                                                                            .id] =
                                                                    'piece';
                                                                if (!_productUsePromotion
                                                                    .containsKey(
                                                                        product
                                                                            .id)) {
                                                                  _productUsePromotion[
                                                                          product
                                                                              .id] =
                                                                      false;
                                                                }
                                                              });
                                                            }
                                                          },
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(8),
                                                          child: Container(
                                                            margin:
                                                                const EdgeInsets
                                                                    .symmetric(
                                                                    horizontal:
                                                                        8,
                                                                    vertical:
                                                                        4),
                                                            padding:
                                                                const EdgeInsets
                                                                    .all(12),
                                                            decoration:
                                                                BoxDecoration(
                                                              color: isSelected
                                                                  ? const Color(
                                                                      0xFFDCFCE7)
                                                                  : Colors
                                                                      .white,
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                          8),
                                                              border:
                                                                  Border.all(
                                                                color: isSelected
                                                                    ? const Color(
                                                                        0xFF10B981)
                                                                    : Colors
                                                                        .grey
                                                                        .shade300,
                                                                width:
                                                                    isSelected
                                                                        ? 2
                                                                        : 1,
                                                              ),
                                                            ),
                                                            child: Row(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Padding(
                                                                  padding:
                                                                      const EdgeInsets
                                                                          .only(
                                                                          right:
                                                                              12),
                                                                  child: Icon(
                                                                    isSelected
                                                                        ? Icons
                                                                            .check_circle
                                                                        : Icons
                                                                            .radio_button_unchecked,
                                                                    color: isSelected
                                                                        ? const Color(
                                                                            0xFF10B981)
                                                                        : Colors
                                                                            .grey[400],
                                                                    size: 24,
                                                                  ),
                                                                ),
                                                                Expanded(
                                                                  child: Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: [
                                                                      Text(
                                                                        product
                                                                            .name,
                                                                        style:
                                                                            TextStyle(
                                                                          fontWeight:
                                                                              FontWeight.bold,
                                                                          fontSize:
                                                                              16,
                                                                          color: isSelected
                                                                              ? const Color(0xFF1F2937)
                                                                              : Colors.grey[800],
                                                                        ),
                                                                      ),
                                                                      const SizedBox(
                                                                          height:
                                                                              4),
                                                                      Text(
                                                                        '${product.price.toStringAsFixed(0)} ₮',
                                                                        style:
                                                                            const TextStyle(
                                                                          color:
                                                                              Color(0xFF6366F1),
                                                                          fontWeight:
                                                                              FontWeight.w700,
                                                                          fontSize:
                                                                              18,
                                                                        ),
                                                                      ),
                                                                      if (isSelected) ...[
                                                                        const SizedBox(
                                                                            height:
                                                                                12),
                                                                        GestureDetector(
                                                                          behavior:
                                                                              HitTestBehavior.opaque,
                                                                          onTap:
                                                                              () {}, // Товч/тоо талбар дээр дарахад карт сонголт өөрчлөгдөхгүй
                                                                          child:
                                                                              Row(
                                                                            children: [
                                                                              // Хасах товч
                                                                              Container(
                                                                                width: 36,
                                                                                height: 36,
                                                                                decoration: BoxDecoration(
                                                                                  color: Colors.grey[200],
                                                                                  borderRadius: BorderRadius.circular(8),
                                                                                ),
                                                                                child: IconButton(
                                                                                  padding: EdgeInsets.zero,
                                                                                  splashRadius: 20,
                                                                                  icon: const Icon(Icons.remove, size: 20, color: Color(0xFF1F2937)),
                                                                                  onPressed: () {
                                                                                    setState(() {
                                                                                      if (quantity > 1) {
                                                                                        _productQuantities[product.id] = quantity - 1;
                                                                                      }
                                                                                    });
                                                                                  },
                                                                                ),
                                                                              ),
                                                                              const SizedBox(width: 8),
                                                                              // Quantity input
                                                                              SizedBox(
                                                                                width: 72,
                                                                                height: 36,
                                                                                child: TextFormField(
                                                                                  key: ValueKey('qty_${product.id}_$quantity'),
                                                                                  textAlign: TextAlign.center,
                                                                                  initialValue: quantity.toString(),
                                                                                  keyboardType: TextInputType.number,
                                                                                  inputFormatters: [
                                                                                    FilteringTextInputFormatter.digitsOnly,
                                                                                  ],
                                                                                  decoration: InputDecoration(
                                                                                    isDense: true,
                                                                                    contentPadding: EdgeInsets.zero,
                                                                                    border: OutlineInputBorder(
                                                                                      borderRadius: BorderRadius.circular(8),
                                                                                      borderSide: BorderSide(color: Colors.grey[300]!),
                                                                                    ),
                                                                                    enabledBorder: OutlineInputBorder(
                                                                                      borderRadius: BorderRadius.circular(8),
                                                                                      borderSide: BorderSide(color: Colors.grey[300]!),
                                                                                    ),
                                                                                    focusedBorder: OutlineInputBorder(
                                                                                      borderRadius: BorderRadius.circular(8),
                                                                                      borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
                                                                                    ),
                                                                                    filled: true,
                                                                                    fillColor: Colors.white,
                                                                                    hintText: '0',
                                                                                  ),
                                                                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                                                                                  onChanged: (v) {
                                                                                    setState(() {
                                                                                      final n = int.tryParse(v);
                                                                                      if (n != null && n > 0) {
                                                                                        _productQuantities[product.id] = n;
                                                                                      }
                                                                                    });
                                                                                  },
                                                                                ),
                                                                              ),
                                                                              const SizedBox(width: 8),
                                                                              // Plus button
                                                                              Container(
                                                                                width: 36,
                                                                                height: 36,
                                                                                decoration: BoxDecoration(
                                                                                  color: const Color(0xFF6366F1),
                                                                                  borderRadius: BorderRadius.circular(8),
                                                                                ),
                                                                                child: IconButton(
                                                                                  padding: EdgeInsets.zero,
                                                                                  icon: const Icon(Icons.add, size: 20, color: Colors.white),
                                                                                  onPressed: () {
                                                                                    setState(() {
                                                                                      _productQuantities[product.id] = quantity + 1;
                                                                                    });
                                                                                  },
                                                                                ),
                                                                              ),
                                                                              const SizedBox(width: 12),
                                                                              // Unit dropdown
                                                                              Expanded(
                                                                                child: Container(
                                                                                  height: 36,
                                                                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                                                                  decoration: BoxDecoration(
                                                                                    color: Colors.grey[100],
                                                                                    borderRadius: BorderRadius.circular(8),
                                                                                    border: Border.all(color: Colors.grey[300]!),
                                                                                  ),
                                                                                  child: DropdownButton<String>(
                                                                                    value: unitMode,
                                                                                    isExpanded: true,
                                                                                    underline: const SizedBox(),
                                                                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1F2937)),
                                                                                    items: const [
                                                                                      DropdownMenuItem(value: 'piece', child: Text('Ширхэг')),
                                                                                      DropdownMenuItem(value: 'box', child: Text('Хайрцаг')),
                                                                                    ],
                                                                                    onChanged: (v) {
                                                                                      if (v != null) {
                                                                                        setState(() {
                                                                                          _productUnitModes[product.id] = v;
                                                                                        });
                                                                                      }
                                                                                    },
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                            ],
                                                                          ),
                                                                        ),
                                                                        if (unitsPerBox >
                                                                                1 &&
                                                                            unitMode ==
                                                                                'box')
                                                                          Padding(
                                                                            padding:
                                                                                const EdgeInsets.only(top: 6),
                                                                            child:
                                                                                Row(
                                                                              children: [
                                                                                Icon(Icons.info_outline, size: 14, color: Colors.grey[600]),
                                                                                const SizedBox(width: 4),
                                                                                Text(
                                                                                  '1 хайрцаг = $unitsPerBox ширхэг',
                                                                                  style: TextStyle(
                                                                                    fontSize: 12,
                                                                                    color: Colors.grey[600],
                                                                                    fontStyle: FontStyle.italic,
                                                                                  ),
                                                                                ),
                                                                              ],
                                                                            ),
                                                                          ),
                                                                        if (unitMode ==
                                                                                'box' &&
                                                                            unitsPerBox >
                                                                                1)
                                                                          Padding(
                                                                            padding:
                                                                                const EdgeInsets.only(top: 6),
                                                                            child:
                                                                                Text(
                                                                              'Нийт: ${quantity * unitsPerBox} ширхэг',
                                                                              style: TextStyle(
                                                                                fontSize: 12,
                                                                                color: Colors.grey[700],
                                                                                fontWeight: FontWeight.w600,
                                                                              ),
                                                                            ),
                                                                          ),
                                                                        const SizedBox(
                                                                            height:
                                                                                8),
                                                                        Row(
                                                                          crossAxisAlignment:
                                                                              CrossAxisAlignment.center,
                                                                          children: [
                                                                            Text(
                                                                              'Хямдрал: ',
                                                                              style: TextStyle(
                                                                                fontSize: 13,
                                                                                color: Colors.grey[700],
                                                                                fontWeight: FontWeight.w500,
                                                                              ),
                                                                            ),
                                                                            Container(
                                                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                                              decoration: BoxDecoration(
                                                                                color: Colors.white,
                                                                                borderRadius: BorderRadius.circular(10),
                                                                                border: Border.all(color: Colors.grey.shade300),
                                                                              ),
                                                                              child: Text(
                                                                                '${(product.discountPercent ?? 0).clamp(0, 100)} %',
                                                                                style: const TextStyle(
                                                                                  fontSize: 13,
                                                                                  fontWeight: FontWeight.w700,
                                                                                  color: Color(0xFF111827),
                                                                                ),
                                                                              ),
                                                                            ),
                                                                            const SizedBox(width: 12),
                                                                            Expanded(
                                                                              child: Container(
                                                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                                                                decoration: BoxDecoration(
                                                                                  color: Colors.white,
                                                                                  borderRadius: BorderRadius.circular(10),
                                                                                  border: Border.all(color: Colors.grey.shade300),
                                                                                ),
                                                                                child: Text(
                                                                                  product.promotionText ?? 'Урамшуулал: –',
                                                                                  maxLines: 1,
                                                                                  overflow: TextOverflow.ellipsis,
                                                                                  style: TextStyle(
                                                                                    fontSize: 13,
                                                                                    color: Colors.grey[800],
                                                                                    fontWeight: FontWeight.w600,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                            ),
                                                                          ],
                                                                        ),
                                                                      ],
                                                                    ],
                                                                  ),
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

                                        // Add selected button
                                        if (_selectedProductIds.isNotEmpty) ...[
                                          const SizedBox(height: 16),
                                          SizedBox(
                                            width: double.infinity,
                                            height: 56,
                                            child: ElevatedButton.icon(
                                              onPressed: () {
                                                final int count =
                                                    _selectedProductIds.length;
                                                _addAllSelectedProductsToCart();
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                        '✅ $count бараа сагсанд нэмэгдлээ!'),
                                                    backgroundColor:
                                                        const Color(0xFF10B981),
                                                    duration: const Duration(
                                                        seconds: 2),
                                                  ),
                                                );
                                              },
                                              icon: const Icon(
                                                  Icons.add_shopping_cart,
                                                  size: 28),
                                              label: Text(
                                                '${_selectedProductIds.length} бараа сагсанд нэмэх ➕',
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFF10B981),
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                elevation: 4,
                                              ),
                                            ),
                                          ),
                                        ],

                                        const SizedBox(height: 12),
                                        SizedBox(
                                            width: double.infinity,
                                            child: addBtn),
                                      ],
                                    );
                                  },
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
                                              '${_currentProduct!.price.toStringAsFixed(0)} ₮',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF10B981),
                                              ),
                                            ),
                                          ],
                                        ),
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
                                // Тоо оруулах
                                TextFormField(
                                  controller: _currentQuantityController,
                                  enabled: _selectedShopName != null,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: 'Тоо / Ширхэг',
                                    hintText: _selectedShopName == null
                                        ? 'Эхлээд дэлгүүр сонгоно уу'
                                        : 'Тоо оруулна уу',
                                    prefixIcon: const Icon(Icons.numbers),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                // Нэмэх товч - ТОМ, ТОД
                                SizedBox(
                                  width: double.infinity,
                                  height: 50,
                                  child: ElevatedButton.icon(
                                    onPressed: (_selectedShopName == null ||
                                            _currentProduct == null ||
                                            _currentQuantityController
                                                .text.isEmpty)
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
                                      backgroundColor: const Color(0xFF10B981),
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

                          // Сонгосон бараанууд
                          if (_selectedItems.isNotEmpty) ...[
                            CartItemsWidget(
                              items: _selectedItems,
                              onRemoveItem: _removeProductFromCart,
                              onQuantityChanged: _updateCartItemQuantity,
                              totalAmount: _totalAmount,
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
                                : _showPaymentMethodDialog,
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
                                  : 'Борлуулалт бүртгэх',
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
