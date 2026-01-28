import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:convert';
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
  String? _currentProductId;
  Product? _currentProduct;
  final _currentQuantityController = TextEditingController();
  final Map<String, int> _productQuantities =
      {}; // Store quantities for each product

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
        await warehouseProvider.refreshProducts();
        if (mounted) productProvider.setProducts(warehouseProvider.products);
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
                        setState(() {
                          _selectedShopName = shop.name;
                          _shopFieldController.text = shop.name;
                        });
                        Navigator.pop(ctx);
                        _checkShopCreditStatus(shop.name);
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
      _currentProductId = null;
      _currentProduct = null;
      _currentQuantityController.clear();
    });
  }

  // Add all selected products with default quantity of 1
  void _addAllSelectedProductsToCart() {
    if (_selectedShopName == null || _selectedProductIds.isEmpty) {
      return;
    }

    final productProvider =
        Provider.of<ProductProvider>(context, listen: false);
    int addedCount = 0;

    for (final productId in _selectedProductIds) {
      final product = productProvider.getProductById(productId);
      if (product == null) continue;

      // Always add 1 quantity
      final quantity = 1;

      // Check if product already in cart
      final existingIndex = _selectedItems.indexWhere(
        (item) => item.productId == productId,
      );

      if (existingIndex >= 0) {
        // Add to existing quantity
        final existingItem = _selectedItems[existingIndex];
        _selectedItems[existingIndex] = SalesItem(
          productId: existingItem.productId,
          productName: existingItem.productName,
          price: existingItem.price,
          quantity: existingItem.quantity + quantity,
        );
      } else {
        // Add new item
        _selectedItems.add(SalesItem(
          productId: product.id,
          productName: product.name,
          price: product.price,
          quantity: quantity,
        ));
      }
      addedCount++;
    }

    setState(() {
      _selectedProductIds.clear();
      _productQuantities.clear();
      _showProductList = false; // Hide product list after adding
      _productSearchController.clear(); // Clear search
    });
  }

  void _removeProductFromCart(int index) {
    setState(() {
      _selectedItems.removeAt(index);
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Төлбөрийн төрөл сонгох'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildPaymentOption(
              'Бэлэн',
              Icons.money_rounded,
              const Color(0xFF10B981),
              () {
                Navigator.pop(context);
                _processPurchase('бэлэн');
              },
            ),
            const SizedBox(height: 12),
            _buildPaymentOption(
              'Данс',
              Icons.account_balance_wallet_rounded,
              const Color(0xFF3B82F6),
              () {
                Navigator.pop(context);
                _processPurchase('данс');
              },
            ),
            const SizedBox(height: 12),
            _buildPaymentOption(
              'Зээл',
              Icons.credit_card_rounded,
              const Color(0xFF8B5CF6),
              () {
                Navigator.pop(context);
                _processPurchase('зээл');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Цуцлах'),
          ),
        ],
      ),
    );
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
                _currentProductId = id;
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

  Widget _buildPaymentOption(
      String title, IconData icon, Color color, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _processPurchase(String paymentMethod) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Баримт хэвлэх
      await _printReceipt(paymentMethod);

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

      debugPrint('📤 Warehouse backend руу захиалга илгээж байна...');
      debugPrint('   • Дэлгүүр ID: $customerId');
      debugPrint('   • Барааны тоо: ${items.length}');
      debugPrint('   • Төлбөрийн төрөл: $backendPaymentMethod');

      // Create order via warehouse backend API
      final result = await warehouseProvider.createOrder(
        customerId: customerId,
        items: items,
        orderType: 'Store', // or 'Market' depending on your needs
        paymentMethod: backendPaymentMethod,
      );

      debugPrint('✅ Захиалга амжилттай илгээгдлээ!');
      debugPrint('   • Order ID: ${result['order']?['id']}');
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

  Future<Uint8List> _generateQrCodeImage(String data) async {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.L,
      color: const Color(0xFF000000),
      emptyColor: const Color(0xFFFFFFFF),
    );

    final picRecorder = ui.PictureRecorder();
    final canvas = Canvas(picRecorder);
    const size = 200.0;
    painter.paint(canvas, const Size(size, size));

    final picture = picRecorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  Future<void> _printReceipt(String paymentMethod) async {
    if (_selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Хамгийн багадаа нэг бараа сонгоно уу'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final totalAmount = _totalAmount;
    final now = DateTime.now();

    // QR code мэдээлэл үүсгэх (JSON формат)
    final qrData = {
      'items': _selectedItems.map((item) => item.toJson()).toList(),
      'total': totalAmount,
      'paymentMethod': paymentMethod,
      'location': _selectedShopName ?? 'Дэлгүүр',
      'date': now.toIso8601String(),
      'salesperson': authProvider.user?.name ?? '',
    };
    final qrDataString = jsonEncode(qrData);

    // QR code image үүсгэх
    final qrImageBytes = await _generateQrCodeImage(qrDataString);
    final qrImage = pw.MemoryImage(qrImageBytes);

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'БОРЛУУЛАЛТЫН БАРИМТ',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 10),
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Text('Дэлгүүр: $_selectedShopName'),
              pw.SizedBox(height: 10),
              pw.Divider(),
              pw.SizedBox(height: 5),
              // Олон барааны мэдээлэл
              for (var item in _selectedItems) ...[
                pw.Text('${item.productName}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 3),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                        '${item.quantity} x ${item.price.toStringAsFixed(0)} ₮'),
                    pw.Text('${item.total.toStringAsFixed(0)} ₮',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 8),
              ],
              pw.Divider(),
              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Нийт үнэ:',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '${totalAmount.toStringAsFixed(0)} ₮',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              if (_notesController.text.isNotEmpty) ...[
                pw.Text('Тэмдэглэл: ${_notesController.text}'),
                pw.SizedBox(height: 10),
              ],
              pw.Divider(),
              pw.SizedBox(height: 5),
              pw.Text('Худалдагч: ${authProvider.user?.name ?? ''}'),
              pw.SizedBox(height: 5),
              pw.Text('Төлбөрийн төрөл: ${paymentMethod.toUpperCase()}'),
              pw.SizedBox(height: 5),
              pw.Text('Огноо: ${now.toString().split('.')[0]}'),
              pw.SizedBox(height: 10),
              pw.Text(
                'Баярлалаа!',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontStyle: pw.FontStyle.italic,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 10),
              // QR Code
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Image(qrImage, width: 150, height: 150),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'QR Code',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
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
      body: SingleChildScrollView(
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
                      // Дэлгүүр сонгох — дарж жагсаалтаас сонгох (зөвхөн нэр харагдана)
                      Consumer2<ShopProvider, WarehouseProvider>(
                        builder: (context, shopProvider, warehouseProvider, child) {
                          if (shopProvider.shops.isEmpty &&
                              warehouseProvider.connected &&
                              !_shopLoadAttempted) {
                            _shopLoadAttempted = true;
                            WidgetsBinding.instance.addPostFrameCallback((_) async {
                              if (!mounted) return;
                              final wp = Provider.of<WarehouseProvider>(context, listen: false);
                              final sp = Provider.of<ShopProvider>(context, listen: false);
                              final ap = Provider.of<AuthProvider>(context, listen: false);
                              await wp.refreshShops(authProvider: ap);
                              if (mounted) sp.setShops(wp.shops);
                            });
                          }
                          return GestureDetector(
                            onTap: () => _openShopPicker(context, shopProvider),
                            child: AbsorbPointer(
                              child: TextFormField(
                                controller: _shopFieldController,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: '🏪 Дэлгүүр хайж сонгох',
                                  hintText: shopProvider.shops.isEmpty
                                      ? 'Дэлгүүр татагдаагүй байна'
                                      : 'Дарж дэлгүүр сонгох',
                                  prefixIcon: const Icon(Icons.store,
                                      color: Color(0xFFEF4444)),
                                  suffixIcon: _selectedShopName != null
                                      ? IconButton(
                                          icon: const Icon(Icons.clear),
                                          onPressed: () {
                                            setState(() {
                                              _selectedShopName = null;
                                              _shopFieldController.clear();
                                            });
                                          },
                                        )
                                      : const Icon(Icons.arrow_drop_down),
                                  filled: true,
                                  fillColor: const Color(0xFFFEF2F2),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFEF4444), width: 2),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFEF4444), width: 2),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                        color: Color(0xFFDC2626), width: 3),
                                  ),
                                ),
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.w600),
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
                      ),
                      // Сонгосон дэлгүүрийн мэдээлэл: нэр, бүртгэлийн дугаар, утас, хаяг
                      Consumer<ShopProvider>(
                        builder: (context, shopProvider, _) {
                          if (_selectedShopName == null) return const SizedBox.shrink();
                          final shop = shopProvider.getShopByName(_selectedShopName!);
                          if (shop == null) return const SizedBox.shrink();
                          final regText = (shop.registrationNumber != null &&
                                  shop.registrationNumber!.isNotEmpty)
                              ? shop.registrationNumber!
                              : '–';
                          final phoneText = shop.phone.isNotEmpty ? shop.phone : '–';
                          final addressText = shop.address.isNotEmpty && shop.address != 'N/A'
                              ? shop.address
                              : '–';
                          return Container(
                            margin: const EdgeInsets.only(top: 12),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Сонгосон дэлгүүр',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  shop.name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.badge_outlined, size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Бүртгэлийн дугаар: ',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                    Expanded(
                                      child: Text(
                                        regText,
                                        style: TextStyle(fontSize: 13, color: Colors.grey[800], fontWeight: FontWeight.w500),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.phone, size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Утас: $phoneText',
                                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.place, size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Хаяг: $addressText',
                                        style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
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
                                final searchText =
                                    _productSearchController.text.toLowerCase();
                                final filteredProducts = (searchText.isEmpty
                                        ? productProvider.products
                                        : productProvider.products.where((p) {
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
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: Colors.blue.shade200, width: 2),
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
                                          : (productProvider.products.isEmpty
                                              ? 'Бараа алга'
                                              : 'Дарж бараа сонгох...'),
                                      prefixIcon:
                                          const Icon(Icons.search, size: 28),
                                      suffixIcon: _productSearchController
                                              .text.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(Icons.clear),
                                              onPressed: () {
                                                setState(() {
                                                  _productSearchController
                                                      .clear();
                                                });
                                              },
                                            )
                                          : const Icon(Icons.arrow_drop_down),
                                      filled: true,
                                      fillColor: Colors.white,
                                    ),
                                    style: const TextStyle(fontSize: 16),
                                    onChanged: (value) {
                                      setState(() {}); // Rebuild to filter
                                    },
                                  ),
                                );

                                // Dropdown
                                final dropdown =
                                    DropdownButtonFormField<String>(
                                  value: _currentProductId,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: 'Бараа',
                                    hintText: _selectedShopName == null
                                        ? 'Эхлээд дэлгүүр сонгоно уу'
                                        : (productProvider.products.isEmpty
                                            ? 'Бараа алга (Шинэ дарж нэмнэ үү)'
                                            : filteredProducts.isEmpty
                                                ? 'Хайлт олдсонгүй'
                                                : 'Бараа сонгоно уу'),
                                    prefixIcon:
                                        const Icon(Icons.inventory_2_outlined),
                                  ),
                                  items: filteredProducts.map((product) {
                                    return DropdownMenuItem(
                                      value: product.id,
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              product.name,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  const TextStyle(fontSize: 14),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${product.price.toStringAsFixed(0)} ₮',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF10B981),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: _selectedShopName == null ||
                                          filteredProducts.isEmpty
                                      ? null
                                      : (value) {
                                          setState(() {
                                            _currentProductId = value;
                                            _currentProduct = productProvider
                                                .getProductById(value!);
                                          });
                                        },
                                );

                                final addBtn = ElevatedButton.icon(
                                  onPressed: _selectedShopName == null
                                      ? null
                                      : _showAddProductDialog,
                                  icon: const Icon(Icons.add_rounded),
                                  label: const Text('Шинэ'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                  ),
                                );

                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    searchBar,
                                    const SizedBox(height: 12),

                                    // Checkbox list with quantities - Show only when tapped
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
                                              color: const Color(0xFF10B981),
                                              width: 2),
                                        ),
                                        child: Column(
                                          children: [
                                            // Header
                                            Container(
                                              padding: const EdgeInsets.all(12),
                                              decoration: const BoxDecoration(
                                                color: Color(0xFF10B981),
                                                borderRadius: BorderRadius.only(
                                                  topLeft: Radius.circular(10),
                                                  topRight: Radius.circular(10),
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
                                                          Icons.check_circle,
                                                          color: Colors.white,
                                                          size: 20),
                                                      const SizedBox(width: 8),
                                                      Text(
                                                        '✓ ${_selectedProductIds.length} бараа сонгосон',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight:
                                                              FontWeight.bold,
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
                                                        });
                                                      },
                                                      style:
                                                          TextButton.styleFrom(
                                                        padding:
                                                            const EdgeInsets
                                                                .symmetric(
                                                                horizontal: 8,
                                                                vertical: 4),
                                                      ),
                                                      child: const Text(
                                                        'Цэвэрлэх',
                                                        style: TextStyle(
                                                            color: Colors.white,
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
                                                itemBuilder: (context, index) {
                                                  final product =
                                                      filteredProducts[index];
                                                  final isSelected =
                                                      _selectedProductIds
                                                          .contains(product.id);
                                                  final quantity =
                                                      _productQuantities[
                                                              product.id] ??
                                                          1;

                                                  return Container(
                                                    margin: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: isSelected
                                                          ? const Color(
                                                              0xFFDCFCE7)
                                                          : Colors.white,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      border: Border.all(
                                                        color: isSelected
                                                            ? const Color(
                                                                0xFF10B981)
                                                            : Colors
                                                                .grey.shade300,
                                                        width:
                                                            isSelected ? 2 : 1,
                                                      ),
                                                    ),
                                                    child: ListTile(
                                                      leading: Checkbox(
                                                        value: isSelected,
                                                        onChanged:
                                                            (bool? checked) {
                                                          setState(() {
                                                            if (checked ==
                                                                true) {
                                                              _selectedProductIds
                                                                  .add(product
                                                                      .id);
                                                              _productQuantities[
                                                                  product
                                                                      .id] = 1;
                                                            } else {
                                                              _selectedProductIds
                                                                  .remove(
                                                                      product
                                                                          .id);
                                                              _productQuantities
                                                                  .remove(
                                                                      product
                                                                          .id);
                                                            }
                                                          });
                                                        },
                                                        activeColor:
                                                            const Color(
                                                                0xFF10B981),
                                                      ),
                                                      title: Text(
                                                        product.name,
                                                        style: TextStyle(
                                                          fontWeight: isSelected
                                                              ? FontWeight.bold
                                                              : FontWeight
                                                                  .normal,
                                                          fontSize: 15,
                                                        ),
                                                      ),
                                                      subtitle: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment.start,
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Text(
                                                            '${product.price.toStringAsFixed(0)} ₮',
                                                            style: const TextStyle(
                                                              color:
                                                                  Color(0xFF059669),
                                                              fontWeight:
                                                                  FontWeight.w600,
                                                            ),
                                                          ),
                                                          if (isSelected) ...[
                                                            const SizedBox(
                                                                height: 8),
                                                            Row(
                                                              children: [
                                                                Text(
                                                                  'Авах тоо: ',
                                                                  style: TextStyle(
                                                                    fontSize: 13,
                                                                    color: Colors.grey[700],
                                                                    fontWeight: FontWeight.w500,
                                                                  ),
                                                                ),
                                                                SizedBox(
                                                                  width: 72,
                                                                  height: 36,
                                                                  child: TextFormField(
                                                                    key: ValueKey('qty_${product.id}'),
                                                                    initialValue: quantity.toString(),
                                                                    keyboardType: TextInputType.number,
                                                                    inputFormatters: [
                                                                      FilteringTextInputFormatter.digitsOnly,
                                                                    ],
                                                                    decoration: InputDecoration(
                                                                      isDense: true,
                                                                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                                                      border: OutlineInputBorder(
                                                                        borderRadius: BorderRadius.circular(8),
                                                                      ),
                                                                      filled: true,
                                                                      fillColor: Colors.white,
                                                                      hintText: '0',
                                                                    ),
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
                                                                const SizedBox(width: 4),
                                                                Text(
                                                                  'ширхэг',
                                                                  style: TextStyle(
                                                                    fontSize: 12,
                                                                    color: Colors.grey[600],
                                                                  ),
                                                                ),
                                                              ],
                                                            ),
                                                          ],
                                                        ],
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
                                                duration:
                                                    const Duration(seconds: 2),
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
                                        width: double.infinity, child: addBtn),
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
                                  border:
                                      Border.all(color: Colors.grey.shade200),
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
                                    if (_currentProduct!.stockQuantity != null)
                                      Text(
                                        'Үлдэгдэл: ${_currentProduct!.stockQuantity} ширхэг',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[700]),
                                      ),
                                    if (_currentProduct!.unitsPerBox != null)
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
                                        _currentQuantityController.text.isEmpty)
                                    ? null
                                    : () {
                                        _addProductToCart();
                                      },
                                icon: const Icon(Icons.add_circle, size: 24),
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
                        Container(
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
                                  Icon(Icons.shopping_cart,
                                      color: Color(0xFF10B981)),
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
                              ...List.generate(_selectedItems.length, (index) {
                                final item = _selectedItems[index];
                                final quantityController =
                                    TextEditingController(
                                  text: item.quantity.toString(),
                                );

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: Colors.grey.shade200),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
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
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 8,
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: const BorderSide(
                                                  color: Color(0xFF10B981),
                                                  width: 2,
                                                ),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                borderSide: const BorderSide(
                                                  color: Color(0xFF10B981),
                                                  width: 2,
                                                ),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(8),
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
                                              quantityController.selection =
                                                  TextSelection(
                                                baseOffset: 0,
                                                extentOffset: quantityController
                                                    .text.length,
                                              );
                                            },
                                            onChanged: (value) {
                                              if (value.isEmpty)
                                                return; // Allow empty for editing
                                              final newQuantity =
                                                  int.tryParse(value);
                                              if (newQuantity != null &&
                                                  newQuantity > 0) {
                                                setState(() {
                                                  _selectedItems[index] =
                                                      SalesItem(
                                                    productId: item.productId,
                                                    productName:
                                                        item.productName,
                                                    price: item.price,
                                                    quantity: newQuantity,
                                                  );
                                                });
                                              }
                                            },
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline,
                                            color: Colors.red),
                                        onPressed: () {
                                          quantityController.dispose();
                                          _removeProductFromCart(index);
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              }),
                              const Divider(),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Нийт үнэ:',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  Text(
                                    '${_totalAmount.toStringAsFixed(0)} ₮',
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
                      const SizedBox(height: 32),

                      // Purchase Button
                      SizedBox(
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: (_isLoading ||
                                  _selectedItems.isEmpty ||
                                  _selectedShopName == null)
                              ? null
                              : _showPaymentMethodDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            elevation: 3,
                            shadowColor:
                                const Color(0xFF10B981).withOpacity(0.4),
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
                              : const Icon(Icons.shopping_cart_rounded),
                          label: Text(
                            _isLoading
                                ? 'Боловсруулж байна...'
                                : 'Худалдан авах',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
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
      ),
    );
  }
}
