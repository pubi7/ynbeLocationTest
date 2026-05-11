import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/order_model.dart';
import '../../providers/order_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../services/pos_receipt_service.dart';
import '../../utils/ebarimt_order_return.dart';
import '../../utils/role_utils.dart';
import '../../utils/sales_agent_order_cancel.dart';
import '../../utils/order_owner_utils.dart';
import '../../utils/warehouse_agent_shop_identity_one_file.dart';
import '../../widgets/go_pop_scope.dart';
import '../../widgets/hamburger_menu.dart';
import '../../widgets/bottom_navigation.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  DateTime _selectedDay = DateUtils.dateOnly(DateTime.now());
  bool _didInitSelectedDayByRole = false;

  /// Нэвтрэлтийн `user.id`-аас ялгаатай Agent тоон ID (профайл/логинд хадгалагдсан).
  int? _prefsAgentId;

  /// Гар утсанд eBarimt хэвлэсэн захиалгын ID (prefs-тай ижил түлхүүр).
  Set<String> _localPrintedOrderIds = <String>{};

  /// Дэлгүүр → бараа → нийт ширхэг (хэд хэдэн захиалга нэгтгэнэ).
  final List<String> _pickListShopOrder = [];
  final Map<String, Map<String, _PickListProductAgg>> _pickListByShop = {};

  /// Өдөр сонгоход шүүх өдөр: **захиалга үүссэн** (orderDate).
  /// deliveryDate ихэвчлэн «хүргэх өдөр» (+1) тул түүгээр шүүвэл өнөөдөр
  /// орсон захиалга маргаашийн өдөрт орж харагдах алдаа гардаг.
  DateTime _orderPlacedCalendarDay(Order o) {
    // Backend orderDate ихэвчлэн UTC timestamp (Z) байдаг.
    // UI дээр хэрэглэгч local хуанлийн өдрөөр (Монгол цаг) харна.
    // Тиймээс UTC ирсэн бол local руу хөрвүүлээд local өдрөөр нь шүүнэ.
    final local = o.orderDate.isUtc ? o.orderDate.toLocal() : o.orderDate;
    return DateUtils.dateOnly(local);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitSelectedDayByRole) return;
    _didInitSelectedDayByRole = true;

    final auth = Provider.of<AuthProvider>(context, listen: false);
    final role = auth.userRole;
    if (isManagerRole(role)) {
      _selectedDay = DateUtils.dateOnly(DateTime.now());
      return;
    }

    final now = DateTime.now();
    final addDays = now.weekday == DateTime.saturday ? 2 : 1;
    _selectedDay = DateUtils.dateOnly(now.add(Duration(days: addDays)));
  }

  void _rebuildPickList(List<Order> dayOrders) {
    _pickListShopOrder.clear();
    _pickListByShop.clear();
    for (final o in dayOrders) {
      final shop = o.customerName.trim().isEmpty
          ? 'Дэлгүүр тодорхойгүй'
          : o.customerName.trim();
      if (!_pickListByShop.containsKey(shop)) {
        _pickListShopOrder.add(shop);
        _pickListByShop[shop] = {};
      }
      final pm = _pickListByShop[shop]!;
      for (final it in o.items) {
        final id = it.productId.trim().isEmpty ? it.productName : it.productId;
        final upb = it.unitsPerBox <= 0 ? 1 : it.unitsPerBox;
        final existing = pm[id];
        if (existing == null) {
          pm[id] = _PickListProductAgg(
            productName: it.productName,
            totalPieces: it.quantity,
            unitsPerBox: upb,
          );
        } else {
          existing.totalPieces += it.quantity;
          if (upb > existing.unitsPerBox) {
            existing.unitsPerBox = upb;
          }
        }
      }
    }
  }

  String _formatPickLine(_PickListProductAgg p) {
    final upb = p.unitsPerBox <= 0 ? 1 : p.unitsPerBox;
    final t = p.totalPieces;
    if (upb <= 1) return '$t ширхэг';
    final boxes = t ~/ upb;
    final extra = t % upb;
    if (extra == 0) {
      return '$boxes хайрцаг (нийт $t ш)';
    }
    return '$boxes хайрцаг + $extra ширхэг (нийт $t ш)';
  }

  void _showDayPickListSheet(
    BuildContext context,
    List<Order> visibleOrders,
  ) {
    _rebuildPickList(visibleOrders);
    final dateStr = _selectedDay.toString().split(' ')[0];
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (ctx, scrollController) {
            if (visibleOrders.isEmpty) {
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    '$dateStr — энэ өдөр үүссэн захиалга алга.',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              );
            }
            final totalMap = _aggregatePickListAllShops(visibleOrders);
            final totalEntries = totalMap.entries.toList()
              ..sort((a, b) => a.value.productName
                  .toLowerCase()
                  .compareTo(b.value.productName.toLowerCase()));

            final shopTiles = <Widget>[];
            for (var si = 0; si < _pickListShopOrder.length; si++) {
              final shop = _pickListShopOrder[si];
              final products = _pickListByShop[shop]!;
              final entries = products.entries.toList()
                ..sort((a, b) => a.value.productName
                    .toLowerCase()
                    .compareTo(b.value.productName.toLowerCase()));
              shopTiles.add(
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: Colors.grey.shade200),
                  ),
                  child: ExpansionTile(
                    initiallyExpanded: si == 0,
                    title: Text(
                      shop,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text('${entries.length} төрлийн бараа'),
                    children: [
                      for (final e in entries)
                        ListTile(
                          dense: true,
                          title: Text(
                            e.value.productName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(_formatPickLine(e.value)),
                        ),
                    ],
                  ),
                ),
              );
            }

            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
                  child: Text(
                    '$dateStr — өдрийн хүргэлт',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Нийт авч явах бараа',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: Colors.blue.shade900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${totalEntries.length} төрөл · бүх дэлгүүр нэгтгэсэн',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final e in totalEntries)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: ListTile(
                      dense: true,
                      title: Text(
                        e.value.productName,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(_formatPickLine(e.value)),
                    ),
                  ),
                const SizedBox(height: 8),
                Divider(height: 24, color: Colors.grey.shade300),
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
                  child: Text(
                    'Дэлгүүрээр',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Colors.grey.shade800,
                    ),
                  ),
                ),
                ...shopTiles,
              ],
            );
          },
        );
      },
    );
  }

  /// Бүх дэлгүүрийг нэгтгэсэн өдрийн авах бараа (хайрцаг/ширхэг).
  Map<String, _PickListProductAgg> _aggregatePickListAllShops(
      List<Order> dayOrders) {
    final Map<String, _PickListProductAgg> all = {};
    for (final o in dayOrders) {
      for (final it in o.items) {
        final id =
            it.productId.trim().isEmpty ? it.productName : it.productId;
        final upb = it.unitsPerBox <= 0 ? 1 : it.unitsPerBox;
        final existing = all[id];
        if (existing == null) {
          all[id] = _PickListProductAgg(
            productName: it.productName,
            totalPieces: it.quantity,
            unitsPerBox: upb,
          );
        } else {
          existing.totalPieces += it.quantity;
          if (upb > existing.unitsPerBox) {
            existing.unitsPerBox = upb;
          }
        }
      }
    }
    return all;
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (!mounted) return;
    if (picked == null) return;
    setState(() {
      _selectedDay = DateUtils.dateOnly(picked);
    });
    await _refreshOrders();
  }

  Future<void> _loadLocalPrintedOrderIds() async {
    final s = await readLocallyPrintedOrderIds();
    if (mounted) {
      setState(() => _localPrintedOrderIds = s);
    }
  }

  Future<void> _refreshOrders() async {
    final warehouseProvider =
        Provider.of<WarehouseProvider>(context, listen: false);
    if (warehouseProvider.connected) {
      // Нэвтрэхэд болон өдөр солиход: тухайн өдрийнхийг л татна.
      await Provider.of<OrderProvider>(context, listen: false).fetchOrders(
        warehouseProvider.dio,
        startDate: _selectedDay,
        endDate: _selectedDay,
      );
    }
    if (mounted) await _loadLocalPrintedOrderIds();
  }

  Future<void> _markFulfilled(Order order) async {
    final oid = int.tryParse(order.id);
    if (oid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Захиалгын ID буруу байна')),
      );
      return;
    }

    final warehouse = Provider.of<WarehouseProvider>(context, listen: false);
    final orders = Provider.of<OrderProvider>(context, listen: false);

    if (!warehouse.connected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Серверт холбогдоогүй байна')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    try {
      await warehouse.updateOrderStatus(orderId: oid, status: 'Fulfilled');
      await orders.fetchOrders(
        warehouse.dio,
        startDate: _selectedDay,
        endDate: _selectedDay,
      );
      if (mounted) await _loadLocalPrintedOrderIds();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Захиалга Fulfilled боллоо'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Статус өөрчлөхөд алдаа: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<void> _printAndFulfill(Order order) async {
    final oid = int.tryParse(order.id);
    if (oid == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Захиалгын ID буруу байна')),
      );
      return;
    }

    final role = Provider.of<AuthProvider>(context, listen: false).userRole;
    if (isAgentRole(role) || isManagerRole(role)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Энэ эрхээр баримт хэвлэхгүй (зөвхөн захиалга үүсгэнэ).'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final warehouse = Provider.of<WarehouseProvider>(context, listen: false);
    final orders = Provider.of<OrderProvider>(context, listen: false);

    if (!warehouse.connected) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Серверт холбогдоогүй байна')),
      );
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const PopScope(
        canPop: false,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    try {
      // 1) Баримт хэвлэх
      await PosReceiptService.directPrintOrderReceipt(order);

      // 2) Хэвлэлт амжилттай гэж үзээд eBarimt бүртгүүлэх (ингэвэл сервер дээр ebarimtRegistered болно)
      await warehouse.tryEbarimtRegisterOrder(oid);

      // 3) Mobile дээр статус өөрчлөгдөх үед Weve дээр бас өөрчлөгдөж харагдуулах
      await warehouse.updateOrderStatus(orderId: oid, status: 'Fulfilled');

      // 4) Жагсаалтыг шинэчилнэ
      await orders.fetchOrders(
        warehouse.dio,
        startDate: _selectedDay,
        endDate: _selectedDay,
      );
      if (mounted) await _loadLocalPrintedOrderIds();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Баримт хэвлэх/бүртгэхэд алдаа: $e')),
        );
      }
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() => _prefsAgentId =
          p.getInt(WarehouseAgentShopIdentity.prefsAgentIdKey));
    });
    // Fetch orders from backend when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshOrders();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final role = context.watch<AuthProvider>().userRole;
    return GoPopScope(
      fallbackRoute: '/sales-dashboard',
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          title: const Text('Orders'),
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
            onPressed: _refreshOrders,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded),
            onPressed: () => context.go('/sales-dashboard'),
          ),
        ],
      ),
      drawer: const HamburgerMenu(),
      bottomNavigationBar: const BottomNavigationWidget(),
      body: Consumer<OrderProvider>(
        builder: (context, orderProvider, child) {
          final auth = context.watch<AuthProvider>();
          final myId = (auth.user?.id ?? '').trim();
          final allOrders = orderProvider.orders;
          final roleScopedOrders =
              ((isManagerRole(auth.userRole) || isAgentRole(auth.userRole)) &&
                      myId.isNotEmpty)
              ? allOrders
                  .where((o) => orderSalespersonMatchesCurrentUser(
                        orderSalespersonId: o.salespersonId,
                        currentUserId: myId,
                        agentNumericIdFromPrefs: _prefsAgentId,
                      ))
                  .toList()
              : allOrders;
          final visibleOrders = roleScopedOrders
              .where((o) =>
                  DateUtils.isSameDay(_orderPlacedCalendarDay(o), _selectedDay))
              .toList();

          if (orderProvider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (orderProvider.error != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(
                      orderProvider.error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _refreshOrders,
                      child: const Text('Дахин оролдох'),
                    ),
                  ],
                ),
              ),
            );
          }

          final pendingCount = visibleOrders
              .where((o) => o.status.toLowerCase() == 'pending')
              .length;

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
                        Color(0xFF3B82F6),
                        Color(0xFF2563EB),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.shopping_cart_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Orders',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Manage and track all your orders',
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
                        'Total Orders',
                        '${visibleOrders.length}',
                        Icons.shopping_cart_rounded,
                        const Color(0xFF3B82F6),
                        const Color(0xFFEFF6FF),
                        subtitle: isManagerRole(auth.userRole)
                            ? null
                            : 'Дараад: нийт авч явах + дэлгүүрээр',
                        onTap: isManagerRole(auth.userRole)
                            ? null
                            : () => _showDayPickListSheet(
                                  context,
                                  visibleOrders,
                                ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildStatCard(
                        'Total Value',
                        '\$${visibleOrders.fold(0.0, (sum, order) => sum + order.totalAmount).toStringAsFixed(2)}',
                        Icons.attach_money_rounded,
                        const Color(0xFF10B981),
                        const Color(0xFFECFDF5),
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
                        'Avg Order',
                        '\$${visibleOrders.isNotEmpty ? (visibleOrders.fold(0.0, (sum, order) => sum + order.totalAmount) / visibleOrders.length).toStringAsFixed(2) : '0.00'}',
                        Icons.analytics_rounded,
                        const Color(0xFF8B5CF6),
                        const Color(0xFFF3E8FF),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildStatCard(
                        'Pending',
                        '$pendingCount',
                        Icons.pending_actions_rounded,
                        const Color(0xFFF59E0B),
                        const Color(0xFFFEF3C7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Orders List
                Text(
                  'Захиалга (${_selectedDay.toString().split(' ')[0]})',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                ),
                const SizedBox(height: 16),

                // Date filter row
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        _selectedDay.toString().split(' ')[0],
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: _pickDay,
                        icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                        label: const Text('Өдөр сонгох'),
                      ),
                      IconButton(
                        tooltip: 'Өнөөдөр',
                        onPressed: () async {
                          setState(() {
                            _selectedDay = DateUtils.dateOnly(DateTime.now());
                          });
                          await _refreshOrders();
                        },
                        icon: const Icon(Icons.today_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (visibleOrders.isEmpty)
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
                          Icons.shopping_cart_outlined,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Энэ өдөр үүссэн захиалга алга',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Өөр өдөр сонгоод шалгаарай.',
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
                    itemCount: visibleOrders.length,
                    itemBuilder: (context, index) {
                      final order = visibleOrders[index];
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
                              color: const Color(0xFF3B82F6)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.shopping_cart_rounded,
                              color: Color(0xFF3B82F6),
                              size: 20,
                            ),
                          ),
                          title: Text(
                            order.customerName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('Phone: ${order.customerPhone}'),
                              Text('Status: ${order.status.toUpperCase()}'),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Agent/Manager: хэвлэх үйлдэл харагдахгүй.
                              if (isManagerRole(role) &&
                                  order.status.toLowerCase() == 'pending')
                                IconButton(
                                  icon: const Icon(
                                    Icons.check_circle_rounded,
                                    color: Color(0xFF10B981),
                                  ),
                                  tooltip: 'Fulfilled болгох',
                                  onPressed: () => _markFulfilled(order),
                                )
                              else if (!isAgentRole(role) &&
                                  !isManagerRole(role) &&
                                  order.status.toLowerCase() == 'pending')
                                IconButton(
                                  icon: const Icon(
                                    Icons.print_rounded,
                                    color: Color(0xFF3B82F6),
                                  ),
                                  tooltip: 'Баримт хэвлэх',
                                  onPressed: () => _printAndFulfill(order),
                                )
                              else if (isAgentRole(role) &&
                                  !isManagerRole(role) &&
                                  orderCanSalesAgentCancelOwnPending(
                                    order,
                                    currentUserId: auth.user?.id,
                                    prefsAgentNumericId: _prefsAgentId,
                                    locallyPrintedOrderIds:
                                        _localPrintedOrderIds,
                                  ))
                                IconButton(
                                  icon: const Icon(
                                    Icons.cancel_schedule_send_rounded,
                                    color: Color(0xFFDC2626),
                                  ),
                                  tooltip: 'Захиалга цуцлах',
                                  onPressed: () =>
                                      confirmSalesAgentCancelPendingOrder(
                                        context,
                                        order,
                                      ),
                                )
                              else if (orderCanReturnEbarimtReceipt(order))
                                IconButton(
                                  icon: const Icon(
                                    Icons.undo_rounded,
                                    color: Color(0xFFF59E0B),
                                  ),
                                  tooltip: 'Баримт буцаах',
                                  onPressed: () => confirmReturnEbarimtReceipt(
                                      context, order),
                                ),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '\$${order.totalAmount.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF3B82F6),
                                      fontSize: 16,
                                    ),
                                  ),
                                  Text(
                                    // Show **order created day** (not delivery day) to avoid
                                    // "today's order appears as tomorrow" confusion.
                                    (order.orderDate.isUtc
                                            ? order.orderDate.toLocal()
                                            : order.orderDate)
                                        .toString()
                                        .split(' ')[0],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  if (order.deliveryDate != null &&
                                      DateUtils.dateOnly(order.deliveryDate!) !=
                                          DateUtils.dateOnly(order.orderDate))
                                    Text(
                                      'Хүргэлт: ${order.deliveryDate.toString().split(' ')[0]}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () => context.go('/order-details/${order.id}',
                              extra: order),
                        ),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
    Color backgroundColor, {
    String? subtitle,
    VoidCallback? onTap,
  }) {
    final card = Container(
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
              if (onTap != null)
                Icon(Icons.touch_app_rounded,
                    size: 18, color: color.withValues(alpha: 0.75))
              else
                Icon(Icons.trending_up_rounded,
                    size: 16, color: color.withValues(alpha: 0.7)),
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
          if (subtitle != null && subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                color: color.withValues(alpha: 0.65),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: card,
      ),
    );
  }
}

class _PickListProductAgg {
  final String productName;
  int totalPieces;
  int unitsPerBox;

  _PickListProductAgg({
    required this.productName,
    required this.totalPieces,
    required this.unitsPerBox,
  });
}

// (tabs removed) status changes are synced to server instead.
