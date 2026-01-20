import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../providers/sales_provider.dart';
import '../../widgets/hamburger_menu.dart';
import '../../widgets/bottom_navigation.dart';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  static const _dailyTargetKey = 'sales_daily_target';
  double _dailyTarget = 1000000;

  late DateTime _focusedDay;
  late DateTime _selectedDay;
  String _productQuery = '';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedDay = DateTime(now.year, now.month, now.day);
    _selectedDay = _focusedDay;
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

  String _formatRangeLabel() {
    final dfDay = DateFormat('yyyy-MM-dd');
    return dfDay.format(_selectedDay);
  }

  ({DateTime start, DateTime endExclusive}) _dayRange() {
    final day = DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
    return (start: day, endExclusive: day.add(const Duration(days: 1)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Гүйцэтгэл'),
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: const HamburgerMenu(),
      bottomNavigationBar: const BottomNavigationWidget(currentRoute: '/performance'),
      body: Consumer<SalesProvider>(
        builder: (context, salesProvider, _) {
          final range = _dayRange();
          final selectedTotal = salesProvider.getTotalSalesForDay(_selectedDay);

          final target = _dailyTarget;
          final pct = target <= 0 ? 0.0 : (selectedTotal / target);

          final productCounts = _buildProductCounts(
            salesProvider.getSalesByDateRange(range.start, range.endExclusive),
            query: _productQuery,
          );
          final totalQty = productCounts.fold<int>(0, (sum, e) => sum + e.count);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.insights_rounded, color: Colors.white, size: 32),
                      const SizedBox(height: 16),
                      const Text(
                        'Гүйцэтгэл',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Сонгосон өдрийн гүйцэтгэл: ${_formatRangeLabel()}',
                        style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TableCalendar(
                        firstDay: DateTime.utc(2020, 1, 1),
                        lastDay: DateTime.utc(2035, 12, 31),
                        focusedDay: _focusedDay,
                        selectedDayPredicate: (day) =>
                            day.year == _selectedDay.year && day.month == _selectedDay.month && day.day == _selectedDay.day,
                        calendarFormat: CalendarFormat.month,
                        availableCalendarFormats: const {CalendarFormat.month: 'Month'},
                        headerStyle: const HeaderStyle(
                          titleCentered: true,
                          formatButtonVisible: false,
                        ),
                        onDaySelected: (selectedDay, focusedDay) {
                          setState(() {
                            _selectedDay = DateTime(selectedDay.year, selectedDay.month, selectedDay.day);
                            _focusedDay = DateTime(focusedDay.year, focusedDay.month, focusedDay.day);
                          });
                        },
                        onPageChanged: (focusedDay) {
                          setState(() {
                            _focusedDay = DateTime(focusedDay.year, focusedDay.month, focusedDay.day);
                          });
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildProgressRow(
                        title: 'Сонгосон өдрийн гүйцэтгэл',
                        current: selectedTotal,
                        target: target,
                        progress: pct,
                        color: const Color(0xFF10B981),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Төлөвлөгөөг Settings дээрээс өөрчилнө.',
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Борлуулсан бараа',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          Text(
                            _formatRangeLabel(),
                            style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w700, fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Нийт: $totalQty ширхэг',
                              style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(
                            '${selectedTotal.toStringAsFixed(0)} ₮',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: InputDecoration(
                          hintText: 'Барааны нэрээр хайх',
                          prefixIcon: const Icon(Icons.search_rounded),
                          isDense: true,
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5),
                          ),
                          suffixIcon: _productQuery.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Цэвэрлэх',
                                  onPressed: () => setState(() => _productQuery = ''),
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                        onChanged: (v) => setState(() => _productQuery = v),
                      ),
                      const SizedBox(height: 12),
                      if (productCounts.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            _productQuery.isEmpty ? 'Энэ хугацаанд борлуулалт алга.' : 'Хайлтад таарах бараа олдсонгүй.',
                            style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: productCounts.length,
                          separatorBuilder: (_, __) => Divider(height: 16, color: Colors.grey.shade200),
                          itemBuilder: (context, i) {
                            final item = productCounts[i];
                            return Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.name,
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF6366F1).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${item.count}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: Color(0xFF6366F1),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<_ProductCount> _buildProductCounts(
    List<dynamic> salesInRange, {
    required String query,
  }) {
    // `Sales` type is in provider layer; avoid importing the model here by using dynamic shape.
    // Fields used: productName (String), quantity (int?)
    final q = query.trim().toLowerCase();
    final Map<String, int> counts = {};

    for (final s in salesInRange) {
      final String name = (s.productName as String?)?.trim().isNotEmpty == true ? (s.productName as String).trim() : 'Тодорхойгүй';
      if (q.isNotEmpty && !name.toLowerCase().contains(q)) continue;
      final int qty = (s.quantity as int?) ?? 1;
      counts[name] = (counts[name] ?? 0) + (qty <= 0 ? 1 : qty);
    }

    final list = counts.entries.map((e) => _ProductCount(name: e.key, count: e.value)).toList();
    list.sort((a, b) => b.count.compareTo(a.count));
    return list;
  }

  Widget _buildProgressRow({
    required String title,
    required double current,
    required double target,
    required double progress,
    required Color color,
  }) {
    final pct = (progress * 100).clamp(0, 999).toStringAsFixed(0);
    final capped = progress.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
            Text('$pct%', style: TextStyle(fontWeight: FontWeight.w900, color: color)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: capped,
            minHeight: 10,
            backgroundColor: color.withOpacity(0.12),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${current.toStringAsFixed(0)} ₮ / ${target.toStringAsFixed(0)} ₮',
          style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ],
    );
  }
}

class _ProductCount {
  final String name;
  final int count;

  const _ProductCount({required this.name, required this.count});
}

