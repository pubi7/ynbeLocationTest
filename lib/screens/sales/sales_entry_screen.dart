import 'package:flutter/material.dart';
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
import '../../models/sales_model.dart';
import '../../models/sales_item_model.dart';
import '../../models/product_model.dart';
import '../../widgets/hamburger_menu.dart';
import '../../widgets/bottom_navigation.dart';
import '../../widgets/add_shop_dialog.dart';

class SalesEntryScreen extends StatefulWidget {
  const SalesEntryScreen({super.key});

  @override
  State<SalesEntryScreen> createState() => _SalesEntryScreenState();
}

class _SalesEntryScreenState extends State<SalesEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  
  String? _selectedShopName;
  
  // Олон бараа сонгох
  List<SalesItem> _selectedItems = [];
  String? _currentProductId;
  Product? _currentProduct;
  final _currentQuantityController = TextEditingController();
  
  bool _isLoading = false;

  @override
  void dispose() {
    _currentQuantityController.dispose();
    _notesController.dispose();
    super.dispose();
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
  
  void _removeProductFromCart(int index) {
    setState(() {
      _selectedItems.removeAt(index);
    });
  }
  
  
  void _checkShopCreditStatus(String shopName) {
    final salesProvider = Provider.of<SalesProvider>(context, listen: false);
    final shopProvider = Provider.of<ShopProvider>(context, listen: false);
    
    // Зээлээр авсан төлбөр хийгээгүй эсэхийг шалгах
    final hasUnpaidCredit = shopProvider.hasUnpaidCredit(shopName, salesProvider.sales);
    
    if (hasUnpaidCredit) {
      final unpaidAmount = shopProvider.getUnpaidCreditAmount(shopName, salesProvider.sales);
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
  
  void _showAddShopDialog() {
    showDialog(
      context: context,
      builder: (context) => AddShopDialog(
        onShopAdded: (shopName) {
          setState(() {
            _selectedShopName = shopName;
          });
        },
      ),
    );
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
              'Билэн',
              Icons.money_rounded,
              const Color(0xFF10B981),
              () {
                Navigator.pop(context);
                _processPurchase('билэн');
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

  Widget _buildPaymentOption(String title, IconData icon, Color color, VoidCallback onTap) {
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
            content: Text('$paymentMethod төлбөрөөр худалдан авалт амжилттай!'),
            backgroundColor: Colors.green,
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
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);

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
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        paymentMethod: paymentMethod,
        latitude: latitude,
        longitude: longitude,
        quantity: item.quantity,
        ipAddress: ipAddress,
      );

      await salesProvider.addSale(sale);
    }
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
      print('  - ${item.productName}: ${item.quantity} x ${item.price.toStringAsFixed(0)} ₮ = ${item.total.toStringAsFixed(0)} ₮');
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
                pw.Text('${item.productName}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 3),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('${item.quantity} x ${item.price.toStringAsFixed(0)} ₮'),
                    pw.Text('${item.total.toStringAsFixed(0)} ₮', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
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
      bottomNavigationBar: const BottomNavigationWidget(currentRoute: '/sales-entry'),
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
                    // Дэлгүүр сонгох
                    Consumer<ShopProvider>(
                      builder: (context, shopProvider, child) {
                        return Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _selectedShopName,
                                decoration: const InputDecoration(
                                  labelText: 'Дэлгүүр',
                                  hintText: 'Сонгоно уу',
                                  prefixIcon: Icon(Icons.location_on_outlined),
                                ),
                                items: shopProvider.shops.map((shop) {
                                  return DropdownMenuItem(
                                    value: shop.name,
                                    child: Text(shop.name),
                                  );
                                }).toList(),
                                onChanged: (value) {
                                  setState(() {
                                    _selectedShopName = value;
                                  });
                                  // Дэлгүүр сонгохдоо зээлээр авсан төлбөр хийгээгүй эсэхийг шалгах
                                  if (value != null) {
                                    _checkShopCreditStatus(value);
                                  }
                                },
                                validator: (value) {
                                  if (value == null) {
                                    return 'Дэлгүүр сонгоно уу';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () {
                                _showAddShopDialog();
                              },
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Шинэ'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
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
                          // Бараа сонгох
                          Consumer<ProductProvider>(
                            builder: (context, productProvider, child) {
                              return DropdownButtonFormField<String>(
                                value: _currentProductId,
                                decoration: InputDecoration(
                                  labelText: 'Бараа',
                                  hintText: _selectedShopName == null 
                                      ? 'Эхлээд дэлгүүр сонгоно уу'
                                      : 'Бараа сонгоно уу',
                                  prefixIcon: const Icon(Icons.inventory_2_outlined),
                                ),
                                items: productProvider.products.map((product) {
                                  return DropdownMenuItem(
                                    value: product.id,
                                    child: Text(product.name),
                                  );
                                }).toList(),
                                onChanged: _selectedShopName == null
                                    ? null
                                    : (value) {
                                        setState(() {
                                          _currentProductId = value;
                                          _currentProduct = productProvider.getProductById(value!);
                                        });
                                      },
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
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                            ),
                          if (_currentProduct != null) const SizedBox(height: 16),
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
                          // Нэмэх товч
                          ElevatedButton.icon(
                            onPressed: (_selectedShopName == null || 
                                        _currentProduct == null || 
                                        _currentQuantityController.text.isEmpty)
                                ? null
                                : () {
                                    _addProductToCart();
                                  },
                            icon: const Icon(Icons.add_shopping_cart),
                            label: const Text('Сагсанд нэмэх'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3B82F6),
                              foregroundColor: Colors.white,
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
                                Icon(Icons.shopping_cart, color: Color(0xFF10B981)),
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
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                            '${item.quantity} x ${item.price.toStringAsFixed(0)} ₮ = ${item.total.toStringAsFixed(0)} ₮',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: () => _removeProductFromCart(index),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            const Divider(),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                          shadowColor: const Color(0xFF10B981).withOpacity(0.4),
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
                          _isLoading ? 'Боловсруулж байна...' : 'Худалдан авах',
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
