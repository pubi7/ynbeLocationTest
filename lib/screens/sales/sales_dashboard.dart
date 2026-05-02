import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/mobileUserLogin.dart';
import '../../providers/sales_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../providers/product_provider.dart';
import '../../models/order_model.dart';
import '../../models/sales_model.dart';
import '../../utils/order_schedule_utils.dart';
import '../../widgets/bottom_navigation.dart';
import '../../widgets/hamburger_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widgets/monthly_plan_card.dart';
import 'widgets/modern_stat_card.dart';
import 'widgets/orders_list_section.dart';
import 'widgets/products_for_sale_section.dart';
import 'widgets/quick_actions_section.dart';
import 'widgets/sales_dashboard_header.dart';

class SalesDashboard extends StatefulWidget {
  const SalesDashboard({super.key});

  @override
  State<SalesDashboard> createState() => _SalesDashboardState();
}

class _SalesDashboardState extends State<SalesDashboard> {
  late DateTime _selectedDate;
  static const _dailyTargetKey = 'sales_daily_target';
  static const _monthlyTargetKey = 'sales_monthly_target';
  double _dailyTarget = 1000000;
  double _monthlyTarget = 30000000; // Default 30M ₮
  bool _isLoadingMonthlyTarget = false;
  List<dynamic> _productsForSale = [];
  List<dynamic> _allProductsForSale = []; // All products (for filtering)
  bool _isLoadingProducts = false;
  final _productSearchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedDate = DateUtils.dateOnly(DateTime.now());
    _loadTargets();
    // OrderProvider.notifyListeners / setState нь build фазад хориглогдоно —
    // initState-аас шууд await-ийн өмнөх хэсгийг post-frame руу.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadMonthlyTarget();
      _loadProductsForSale();
      _loadOrders();
      final productProvider =
          Provider.of<ProductProvider>(context, listen: false);
      productProvider.addListener(_onProductsChanged);
    });
  }

  void _onProductsChanged() {
    if (!mounted) return;
    // Provider.notifyListeners() нь build үеэр дуудагдаж болно — setState-ийг frame-ийн дараа.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadProductsForSale();
    });
  }

  Future<void> _loadOrders({DateTime? forDate}) async {
    final warehouseProvider =
        Provider.of<WarehouseProvider>(context, listen: false);
    if (warehouseProvider.connected) {
      final date = forDate ?? _selectedDate;
      final dayStart = DateTime(date.year, date.month, date.day);
      // Өргөн огноо (±7 хоног): timezone, цагийн зөрүүнд шинэ захиалга харагдахгүй болохгүй
      final start = dayStart.subtract(const Duration(days: 7));
      final end = dayStart.add(const Duration(days: 7));
      await Provider.of<OrderProvider>(context, listen: false).fetchOrders(
        warehouseProvider.dio,
        startDate: start,
        endDate: end,
      );
    }
  }

  @override
  void dispose() {
    try {
      final productProvider =
          Provider.of<ProductProvider>(context, listen: false);
      productProvider.removeListener(_onProductsChanged);
    } catch (_) {}
    _productSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadTargets() async {
    final prefs = await SharedPreferences.getInstance();
    final d = prefs.getDouble(_dailyTargetKey);
    if (!mounted) return;
    setState(() {
      _dailyTarget = d ?? _dailyTarget;
    });
  }

  Future<void> _loadMonthlyTarget() async {
    final warehouseProvider =
        Provider.of<WarehouseProvider>(context, listen: false);
    if (!warehouseProvider.connected) {
      // Fallback to local storage
      final prefs = await SharedPreferences.getInstance();
      final m = prefs.getDouble(_monthlyTargetKey);
      if (!mounted) return;
      setState(() {
        _monthlyTarget = m ?? _monthlyTarget;
      });
      return;
    }

    setState(() {
      _isLoadingMonthlyTarget = true;
    });

    try {
      final now = DateTime.now();
      final targetData = await warehouseProvider.getMonthlyTarget(
        year: now.year,
        month: now.month,
      );
      if (!mounted) return;
      setState(() {
        _monthlyTarget =
            (targetData['monthlyTarget'] as num?)?.toDouble() ?? _monthlyTarget;
        _isLoadingMonthlyTarget = false;
      });

      // Save to local storage as backup
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_monthlyTargetKey, _monthlyTarget);
    } catch (e) {
      if (!mounted) return;
      // Fallback to local storage
      final prefs = await SharedPreferences.getInstance();
      final m = prefs.getDouble(_monthlyTargetKey);
      setState(() {
        _monthlyTarget = m ?? _monthlyTarget;
        _isLoadingMonthlyTarget = false;
      });
    }
  }

  Future<void> _loadProductsForSale() async {
    if (!mounted) return;
    final warehouseProvider =
        Provider.of<WarehouseProvider>(context, listen: false);
    final productProvider =
        Provider.of<ProductProvider>(context, listen: false);

    if (!warehouseProvider.connected) {
      // Use local products
      if (!mounted) return;
      setState(() {
        _productsForSale = productProvider.products
            .where((p) => p.price > 0 && (p.stockQuantity ?? 0) > 0)
            .take(10)
            .toList();
        _isLoadingProducts = false;
      });
      return;
    }

    setState(() {
      _isLoadingProducts = true;
    });

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
      // Fallback to local products
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

  List<dynamic> _filterProducts(List<dynamic> products) {
    final query = _productSearchController.text.toLowerCase().trim();
    if (query.isEmpty) {
      return products.take(10).toList(); // Show top 10 when no search
    }
    return products.where((product) {
      final name = product.name?.toLowerCase() ?? '';
      final barcode = (product.barcode ?? '').toLowerCase();
      final productCode = (product.productCode ?? '').toLowerCase();
      return name.contains(query) ||
          barcode.contains(query) ||
          productCode.contains(query);
    }).toList();
  }

  /// Тухайн өдрийн захиалгууд (дэлгэцийн шүүлт, нийт дүн).
  static List<Order> _ordersForCalendarDay(
    List<Order> all,
    DateTime selectedDay,
    String role,
  ) =>
      OrderScheduleUtils.ordersForCalendarDay(all, selectedDay, role);

  /// Хоногийн нийт дүн: эхлээд тухайн өдрийн захиалгаас, байхгүй бол орон нутгийн борлуулалтаас.
  static double _totalSalesForSelectedDay(
    List<Order> orders,
    DateTime selectedDay,
    SalesProvider salesProvider,
    String role,
  ) {
    final dayOrders = _ordersForCalendarDay(orders, selectedDay, role);
    if (dayOrders.isNotEmpty) {
      return dayOrders.fold<double>(0, (a, o) => a + o.totalAmount);
    }
    return salesProvider.getTotalSalesForDay(selectedDay);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 2, 1, 1),
      lastDate: DateTime(now.year + 2, 12, 31),
    );
    if (picked == null) return;
    final newDate = DateUtils.dateOnly(picked);
    setState(() {
      _selectedDate = newDate;
    });
    // Backend-аас тухайн өдрийн захиалгыг татах
    await _loadOrders(forDate: newDate);
    if (mounted) setState(() {});
  }

  String _formatDate(BuildContext context, DateTime d) {
    return MaterialLocalizations.of(context).formatMediumDate(d);
  }

  String _formatTime(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// Өдрийн барааны задрал: тухайн өдрийн backend захиалга байвал түүний мөрнөөс,
  /// байхгүй бол зөвхөн апп доторх Sales бүртгэлээс (хуудас дахин ачаалсан ч API захиалга харагдана).
  void _showTodaySalesBreakdown(
    BuildContext context,
    List<Sales> sales,
    List<Order> orders,
    DateTime calendarDay,
    double dailyTarget,
    String role,
  ) {
    final start =
        DateTime(calendarDay.year, calendarDay.month, calendarDay.day);
    final end = start.add(const Duration(days: 1));

    final dayOrders = _ordersForCalendarDay(orders, calendarDay, role);

    final Map<String, _Agg> agg = {};
    if (dayOrders.isNotEmpty) {
      for (final o in dayOrders) {
        for (final item in o.items) {
          final key =
              item.productName.trim().isEmpty ? 'N/A' : item.productName.trim();
          final cur = agg[key] ?? _Agg();
          cur.qty += item.quantity;
          cur.amount += item.totalPrice;
          agg[key] = cur;
        }
      }
    } else {
      final todays = sales
          .where((s) => !s.saleDate.isBefore(start) && s.saleDate.isBefore(end))
          .toList();
      for (final s in todays) {
        final key = s.productName.trim().isEmpty ? 'N/A' : s.productName.trim();
        final qty = s.quantity ?? 1;
        final cur = agg[key] ?? _Agg();
        cur.qty += qty;
        cur.amount += s.amount;
        agg[key] = cur;
      }
    }

    final items = agg.entries.toList()
      ..sort((a, b) {
        final q = b.value.qty.compareTo(a.value.qty);
        if (q != 0) return q;
        return b.value.amount.compareTo(a.value.amount);
      });

    final totalQty = items.fold<int>(0, (sum, e) => sum + e.value.qty);
    final totalAmount = items.fold<double>(0, (sum, e) => sum + e.value.amount);
    final pct = dailyTarget <= 0 ? 0.0 : (totalAmount / dailyTarget);
    final pctText = (pct * 100).clamp(0, 999).toStringAsFixed(0);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF8FAFC),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Өдрийн борлуулалт ($pctText%) — ${_formatDate(context, calendarDay)}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${totalQty} ширхэг • ${totalAmount.toStringAsFixed(0)} ₮',
                  style: TextStyle(
                      color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child:
                        const Text('Өнөөдөр борлуулалт бүртгэгдээгүй байна.'),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.65),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final e = items[i];
                        final isTop = i == 0;
                        return Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: isTop
                                    ? const Color(0xFF10B981).withOpacity(0.35)
                                    : Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: (isTop
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFF6366F1))
                                      .withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: isTop
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFF6366F1),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            e.key,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                        if (isTop) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10B981)
                                                  .withOpacity(0.12),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: const Text(
                                              'Хамгийн их',
                                              style: TextStyle(
                                                color: Color(0xFF10B981),
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${e.value.qty} ширхэг',
                                      style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${e.value.amount.toStringAsFixed(0)} ₮',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: const Text('Sales Dashboard'),
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
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () async {
              await _loadOrders(forDate: _selectedDate);
              await _loadProductsForSale();
            },
            tooltip: 'Шинэчлэх',
          ),
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: const Icon(Icons.logout_rounded),
              onPressed: () async {
                final loginProvider = Provider.of<MobileUserLoginProvider>(
                    context,
                    listen: false);
                final authProvider =
                    Provider.of<AuthProvider>(context, listen: false);
                await loginProvider.logout();
                await authProvider.logout();
                if (context.mounted) {
                  context.go('/login');
                }
              },
            ),
          ),
        ],
      ),
      drawer: const HamburgerMenu(),
      bottomNavigationBar: Container(
        child: const BottomNavigationWidget(),
      ),
      body: Consumer2<SalesProvider, OrderProvider>(
        builder: (context, salesProvider, orderProvider, child) {
          final role = context.watch<AuthProvider>().userRole;

          // Сонгосон өдөртой яг таарах захиалгууд (календарийн өдөр)
          final filteredOrders =
              _ordersForCalendarDay(orderProvider.orders, _selectedDate, role)
                ..sort((a, b) => b.orderDate.compareTo(a.orderDate));

          // Сонгосон өдрийн нийт борлуулалт: захиалга (API) эсвэл орон нутгийн Sales
          final totalSalesSelectedDay = _totalSalesForSelectedDay(
            orderProvider.orders,
            _selectedDate,
            salesProvider,
            role,
          );

          // Тугны хувь: өдөр сонгоход тэр өдрийн гүйцэтгэл (өмнө нь зөвхөн "өнөөдөр"-өөр тооцогдож байсан)
          final selectedDayPct =
              _dailyTarget <= 0 ? 0.0 : (totalSalesSelectedDay / _dailyTarget);
          final selectedDayPctText =
              (selectedDayPct * 100).clamp(0, 999).toStringAsFixed(0);

          return RefreshIndicator(
            onRefresh: () async {
              await _loadOrders(forDate: _selectedDate);
              await _loadProductsForSale();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SalesDashboardHeader(
                    role: role,
                    selectedDate: _selectedDate,
                    onPickDate: _pickDate,
                    selectedDayPctText: selectedDayPctText,
                    onTapFlag: () => _showTodaySalesBreakdown(
                      context,
                      salesProvider.sales,
                      orderProvider.orders,
                      _selectedDate,
                      _dailyTarget,
                      role,
                    ),
                    formatDate: _formatDate,
                  ),

                  // Stats Cards Section
                  if (role != 'order')
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Expanded(
                            child: ModernStatCard(
                              title: 'Total Sales',
                              value:
                                  '${totalSalesSelectedDay.toStringAsFixed(0)} ₮',
                              icon: Icons.trending_up_rounded,
                              color: const Color(0xFF10B981),
                              backgroundColor: const Color(0xFFECFDF5),
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Monthly Plan Section
                  if (role != 'order')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: MonthlyPlanCard(
                        monthlyTarget: _monthlyTarget,
                        isLoadingMonthlyTarget: _isLoadingMonthlyTarget,
                      ),
                    ),

                  // Products for Sale Section
                  if (role != 'order')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: ProductsForSaleSection(
                        isLoading: _isLoadingProducts,
                        searchController: _productSearchController,
                        productsForSale: _productsForSale,
                        allProductsForSale: _allProductsForSale,
                        onQueryChanged: (_) {
                          setState(() {
                            _productsForSale =
                                _filterProducts(_allProductsForSale);
                          });
                        },
                        onClearQuery: () {
                          setState(() {
                            _productSearchController.clear();
                            _productsForSale = _filterProducts(_allProductsForSale);
                          });
                        },
                        onShowAll: () {
                          setState(() {
                            _productsForSale = _allProductsForSale;
                          });
                        },
                      ),
                    ),

                  // Orders list - Show ALL orders
                  if (role == 'order')
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: OrdersListSection(
                        selectedDate: _selectedDate,
                        filteredOrders: filteredOrders,
                        isLoading: orderProvider.isLoading,
                        error: orderProvider.error,
                        onTapOrder: (o) =>
                            context.go('/order-details/${o.id}', extra: o),
                        formatDate: _formatDate,
                        formatTime: _formatTime,
                      ),
                    ),

                  // Quick Actions Section
                  // Requirement: Dashboard дээр "худалдан авалт/Record Sale" товч байхгүй.
                  // Sales Entry рүү зөвхөн доод navigation-ийн "Sales" tab-аар орно.
                  if (role == 'order') ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: QuickActionsSection(
                        onTakeOrder: () => context.go('/order-screen'),
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Agg {
  int qty = 0;
  double amount = 0;
}
