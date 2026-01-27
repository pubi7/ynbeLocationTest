import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/mobileUserLogin.dart';
import '../../providers/sales_provider.dart';
import '../../providers/order_provider.dart';
import '../../models/sales_model.dart';
import '../../widgets/bottom_navigation.dart';
import '../../widgets/hamburger_menu.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SalesDashboard extends StatefulWidget {
  const SalesDashboard({super.key});

  @override
  State<SalesDashboard> createState() => _SalesDashboardState();
}

class _SalesDashboardState extends State<SalesDashboard> {
  late DateTime _selectedDate;
  static const _dailyTargetKey = 'sales_daily_target';
  double _dailyTarget = 1000000;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateUtils.dateOnly(DateTime.now());
    _loadTargets();
  }

  Future<void> _loadTargets() async {
    final prefs = await SharedPreferences.getInstance();
    final d = prefs.getDouble(_dailyTargetKey);
    if (!mounted) return;
    setState(() {
      _dailyTarget = d ?? _dailyTarget;
    });
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
    setState(() {
      _selectedDate = DateUtils.dateOnly(picked);
    });
  }

  String _formatDate(BuildContext context, DateTime d) {
    return MaterialLocalizations.of(context).formatMediumDate(d);
  }

  String _formatTime(DateTime d) {
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  void _showTodaySalesBreakdown(BuildContext context, List<Sales> sales, double dailyTarget) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));

    final todays = sales.where((s) => !s.saleDate.isBefore(start) && s.saleDate.isBefore(end)).toList();

    final Map<String, _Agg> agg = {};
    for (final s in todays) {
      final key = s.productName.trim().isEmpty ? 'N/A' : s.productName.trim();
      final qty = s.quantity ?? 1;
      final cur = agg[key] ?? _Agg();
      cur.qty += qty;
      cur.amount += s.amount;
      agg[key] = cur;
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
                  'Өнөөдрийн борлуулалт ($pctText%)',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1E293B),
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${totalQty} ширхэг • ${totalAmount.toStringAsFixed(0)} ₮',
                  style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
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
                    child: const Text('Өнөөдөр борлуулалт бүртгэгдээгүй байна.'),
                  )
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.65),
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
                            border: Border.all(color: isTop ? const Color(0xFF10B981).withOpacity(0.35) : Colors.grey.shade200),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: (isTop ? const Color(0xFF10B981) : const Color(0xFF6366F1)).withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Center(
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: isTop ? const Color(0xFF10B981) : const Color(0xFF6366F1),
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
                                            style: const TextStyle(fontWeight: FontWeight.w800),
                                          ),
                                        ),
                                        if (isTop) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10B981).withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(999),
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
                                      style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${e.value.amount.toStringAsFixed(0)} ₮',
                                style: const TextStyle(fontWeight: FontWeight.w900),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Sales Dashboard'),
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
          Container(
            margin: const EdgeInsets.only(right: 16),
            child: IconButton(
              icon: const Icon(Icons.logout_rounded),
              onPressed: () async {
                final loginProvider = Provider.of<MobileUserLoginProvider>(context, listen: false);
                final authProvider = Provider.of<AuthProvider>(context, listen: false);
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
        child: const BottomNavigationWidget(currentRoute: '/sales-dashboard'),
      ),
      body: Consumer2<SalesProvider, OrderProvider>(
        builder: (context, salesProvider, orderProvider, child) {
          final role = context.watch<AuthProvider>().userRole;
          final now = DateTime.now();
          final todayTotal = salesProvider.getTotalSalesForDay(now);
          final todayPct = _dailyTarget <= 0 ? 0.0 : (todayTotal / _dailyTarget);
          final todayPctText = (todayPct * 100).clamp(0, 999).toStringAsFixed(0);
          
          // Filter orders by selected date
          final selectedDayStart = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
          final selectedDayEnd = selectedDayStart.add(const Duration(days: 1));
          
          final filteredOrders = orderProvider.orders.where((order) {
            final orderDay = DateTime(order.orderDate.year, order.orderDate.month, order.orderDate.day);
            return !orderDay.isBefore(selectedDayStart) && orderDay.isBefore(selectedDayEnd);
          }).toList();
          
          filteredOrders.sort((a, b) => b.orderDate.compareTo(a.orderDate));

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Section with Gradient
                Container(
                  width: double.infinity,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF6366F1),
                        Color(0xFF8B5CF6),
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.person_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Welcome back!',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const Text(
                                    'Sales Staff',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (role != 'order')
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => _showTodaySalesBreakdown(context, salesProvider.sales, _dailyTarget),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.16),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.white.withOpacity(0.22)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.flag_rounded, color: Colors.white, size: 18),
                                        const SizedBox(width: 6),
                                        Text(
                                          '$todayPctText%',
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'Manage your sales and orders efficiently',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Calendar / day filter (defaults to today)
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _pickDate,
                              icon: const Icon(Icons.calendar_month_rounded, color: Colors.white),
                              label: Text(
                                _formatDate(context, _selectedDate),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: BorderSide(color: Colors.white.withOpacity(0.65)),
                                backgroundColor: Colors.white.withOpacity(0.12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white.withOpacity(0.18)),
                              ),
                              child: Text(
                                'Нийт захиалга: ${filteredOrders.length}',
                                style: TextStyle(color: Colors.white.withOpacity(0.95), fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Stats Cards Section
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    children: [
                      if (role != 'order') ...[
                        Expanded(
                          child: _buildModernStatCard(
                            'Total Sales',
                            '\$${salesProvider.getTotalSalesForDay(_selectedDate).toStringAsFixed(2)}',
                            Icons.trending_up_rounded,
                            const Color(0xFF10B981),
                            const Color(0xFFECFDF5),
                          ),
                        ),
                      ] else ...[
                        Expanded(
                          child: _buildModernStatCard(
                            'Orders',
                            '${filteredOrders.length}',
                            Icons.shopping_cart_rounded,
                            const Color(0xFF3B82F6),
                            const Color(0xFFEFF6FF),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Monthly progress removed; only today % badge shown in header.

                // Orders list - Show ALL orders
                if (role == 'order')
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_formatDate(context, _selectedDate)}-ний захиалга',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E293B),
                              ),
                        ),
                        const SizedBox(height: 12),
                        if (orderProvider.isLoading)
                          const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                        else if (orderProvider.error != null)
                          Text(orderProvider.error!, style: const TextStyle(color: Colors.red))
                        else if (filteredOrders.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Text('${_formatDate(context, _selectedDate)}-нд захиалга байхгүй байна.'),
                          )
                        else
                          ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: filteredOrders.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, i) {
                              final o = filteredOrders[i];
                              final statusColor = switch (o.status) {
                                'pending' => const Color(0xFFF59E0B),
                                'confirmed' => const Color(0xFF3B82F6),
                                'delivered' => const Color(0xFF10B981),
                                'cancelled' => const Color(0xFFEF4444),
                                _ => const Color(0xFF64748B),
                              };

                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: () => context.go('/order-details/${o.id}', extra: o),
                                  child: Container(
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: Colors.grey.shade200),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Icon(Icons.receipt_long_rounded, color: statusColor),
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
                                                      o.customerName,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Text(
                                                    _formatTime(o.orderDate),
                                                    style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                o.customerAddress,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(color: Colors.grey.shade600),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.end,
                                          children: [
                                            Text(
                                              '${o.totalAmount.toStringAsFixed(0)} ₮',
                                              style: const TextStyle(fontWeight: FontWeight.w800),
                                            ),
                                            const SizedBox(height: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                              decoration: BoxDecoration(
                                                color: statusColor.withOpacity(0.12),
                                                borderRadius: BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                o.status,
                                                style: TextStyle(color: statusColor, fontWeight: FontWeight.w700, fontSize: 12),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),

                // Quick Actions Section
                // Requirement: Dashboard дээр "худалдан авалт/Record Sale" товч байхгүй.
                // Sales Entry рүү зөвхөн доод navigation-ийн "Sales" tab-аар орно.
                if (role == 'order') ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick Actions',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1E293B),
                              ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildCircularActionButton(
                              context,
                              'Take Order',
                              Icons.shopping_cart_rounded,
                              const Color(0xFF3B82F6),
                              () => context.go('/order-screen'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildModernStatCard(String title, String value, IconData icon, Color color, Color backgroundColor) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const Spacer(),
              Icon(Icons.trending_up_rounded, size: 16, color: color.withOpacity(0.7)),
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
              color: color.withOpacity(0.8),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircularActionButton(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Column(
      children: [
        Container(
          width: 70,
          height: 70,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(35),
              onTap: onTap,
              child: Center(
                child: Icon(
                  icon,
                  color: color,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

}

class _Agg {
  int qty = 0;
  double amount = 0;
}
