import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/sales_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../providers/product_provider.dart';
import '../../models/product_model.dart';
import '../../widgets/hamburger_menu.dart';
import '../../widgets/bottom_navigation.dart';

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key});

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  List<Product> _productsForSale = [];
  List<Product> _allProductsForSale = []; // All products (for filtering)
  bool _isLoadingProducts = false;
  final _productSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProductsForSale();
      // Listen for product changes (e.g. stock updates after orders)
      final productProvider = Provider.of<ProductProvider>(context, listen: false);
      productProvider.addListener(_onProductsChanged);
    });
  }

  void _onProductsChanged() {
    _loadProductsForSale();
  }

  @override
  void dispose() {
    try {
      final productProvider = Provider.of<ProductProvider>(context, listen: false);
      productProvider.removeListener(_onProductsChanged);
    } catch (_) {}
    _productSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadProductsForSale() async {
    final warehouseProvider = Provider.of<WarehouseProvider>(context, listen: false);
    final productProvider = Provider.of<ProductProvider>(context, listen: false);

    if (!warehouseProvider.connected) {
      if (!mounted) return;
      final localProducts = productProvider.products
          .where((p) => p.price > 0 && (p.stockQuantity ?? 0) > 0)
          .toList();
      setState(() {
        _allProductsForSale = localProducts;
        _productsForSale = _filterProducts(localProducts);
        _isLoadingProducts = false;
      });
      return;
    }

    setState(() => _isLoadingProducts = true);
    try {
      final products = await warehouseProvider.getProductsForSale(
        hasStock: true,
        hasPrice: true,
      );
      if (!mounted) return;
      setState(() {
        _allProductsForSale = products;
        _productsForSale = _filterProducts(products);
        _isLoadingProducts = false;
      });
    } catch (e) {
      if (!mounted) return;
      final localProducts = productProvider.products
          .where((p) => p.price > 0 && (p.stockQuantity ?? 0) > 0)
          .toList();
      setState(() {
        _allProductsForSale = localProducts;
        _productsForSale = _filterProducts(localProducts);
        _isLoadingProducts = false;
      });
    }
  }

  List<Product> _filterProducts(List<Product> products) {
    final query = _productSearchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      return products;
    }
    return products.where((product) {
      final name = product.name.toLowerCase();
      final barcode = (product.barcode ?? '').toLowerCase();
      final productCode = (product.productCode ?? '').toLowerCase();
      return name.contains(query) || 
             barcode.contains(query) || 
             productCode.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Sales History'),
        backgroundColor: const Color(0xFF10B981),
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
            icon: const Icon(Icons.arrow_back_ios_rounded),
            onPressed: () => context.go('/sales-dashboard'),
          ),
        ],
      ),
      drawer: const HamburgerMenu(),
      bottomNavigationBar: const BottomNavigationWidget(),
      body: Consumer<SalesProvider>(
        builder: (context, salesProvider, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF10B981),
                        Color(0xFF059669),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.history_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Sales History',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'View all your sales records and performance',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Summary Stats
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Total Sales',
                        '\$${salesProvider.getTotalSales().toStringAsFixed(2)}',
                        Icons.trending_up_rounded,
                        const Color(0xFF10B981),
                        const Color(0xFFECFDF5),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildStatCard(
                        'Total Records',
                        '${salesProvider.sales.length}',
                        Icons.receipt_rounded,
                        const Color(0xFF3B82F6),
                        const Color(0xFFEFF6FF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Additional Stats Row
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Avg Sale',
                        '\$${salesProvider.sales.isNotEmpty ? (salesProvider.getTotalSales() / salesProvider.sales.length).toStringAsFixed(2) : '0.00'}',
                        Icons.analytics_rounded,
                        const Color(0xFF8B5CF6),
                        const Color(0xFFF3E8FF),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildStatCard(
                        'This Month',
                        '\$${salesProvider.getTotalSales().toStringAsFixed(2)}',
                        Icons.calendar_month_rounded,
                        const Color(0xFFF59E0B),
                        const Color(0xFFFEF3C7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Зарагдах бараа (Products for Sale)
                Container(
                  width: double.infinity,
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
                          const Icon(Icons.shopping_bag_rounded, color: Color(0xFF6366F1), size: 24),
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
                          if (_isLoadingProducts)
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Бараа хайх талбар
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[300]!, width: 1),
                        ),
                        child: TextField(
                          controller: _productSearchController,
                          decoration: InputDecoration(
                            labelText: '🔍 Бараа хайх',
                            hintText: 'Барааны нэр, баркод эсвэл SKU',
                            prefixIcon: const Icon(Icons.search, size: 24, color: Color(0xFF6366F1)),
                            suffixIcon: _productSearchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _productSearchController.clear();
                                        _productsForSale = _filterProducts(_allProductsForSale);
                                      });
                                    },
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
                              borderSide: const BorderSide(color: Color(0xFF6366F1), width: 2),
                            ),
                          ),
                          style: const TextStyle(fontSize: 16),
                          onChanged: (value) {
                            setState(() {
                              _productsForSale = _filterProducts(_allProductsForSale);
                            });
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_productsForSale.isEmpty && !_isLoadingProducts)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Center(
                            child: Column(
                              children: [
                                Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                                const SizedBox(height: 12),
                                Text(
                                  _productSearchController.text.isNotEmpty
                                      ? 'Хайлтад тохирох бараа олдсонгүй'
                                      : 'Зарагдах бараа олдсонгүй',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ...(_productsForSale.map((product) {
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
                                            '${product.price.toStringAsFixed(0)} ₮',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF10B981),
                                            ),
                                          ),
                                          if (product.stockQuantity != null) ...[
                                            const SizedBox(width: 12),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: product.stockQuantity! > 10
                                                    ? const Color(0xFFECFDF5)
                                                    : const Color(0xFFFEF3C7),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                'Үлдэгдэл: ${product.stockQuantity}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: product.stockQuantity! > 10
                                                      ? const Color(0xFF059669)
                                                      : const Color(0xFFD97706),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList()),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Sales Records List
                Text(
                  'All Sales Records',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 16),

                if (salesProvider.sales.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No sales records yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start recording sales to see your history here.',
                          style: TextStyle(
                            color: Colors.grey[500],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: salesProvider.sales.length,
                    itemBuilder: (context, index) {
                      final sale = salesProvider.sales[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.sell_rounded,
                              color: Color(0xFF10B981),
                              size: 20,
                            ),
                          ),
                          title: Text(
                            sale.productName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('Location: ${sale.location}'),
                              if (sale.notes != null) Text('Notes: ${sale.notes}'),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '\$${sale.amount.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF10B981),
                                  fontSize: 16,
                                ),
                              ),
                              Text(
                                sale.saleDate.toString().split(' ')[0],
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          onTap: () => _showSalesDetail(context, sale),
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, Color backgroundColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const Spacer(),
              Icon(Icons.trending_up_rounded, size: 16, color: color.withValues(alpha: 0.7)),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: color.withValues(alpha: 0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  void _showSalesDetail(BuildContext context, dynamic sale) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.sell, color: Color(0xFF10B981)),
            const SizedBox(width: 8),
            const Text('Sales Details'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Product Name', sale.productName),
              _buildDetailRow('Location', sale.location),
              _buildDetailRow('Amount', '\$${sale.amount.toStringAsFixed(2)}', isAmount: true),
              _buildDetailRow('Date', sale.saleDate.toString().split(' ')[0]),
              _buildDetailRow('Time', sale.saleDate.toString().split(' ')[1].substring(0, 8)),
              if (sale.notes != null && sale.notes!.isNotEmpty) 
                _buildDetailRow('Notes', sale.notes!),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isAmount = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: isAmount ? const Color(0xFF10B981) : Colors.black87,
                fontWeight: isAmount ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}