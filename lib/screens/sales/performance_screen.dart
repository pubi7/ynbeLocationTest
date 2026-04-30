import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../models/sales_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sales_provider.dart';
import '../../widgets/hamburger_menu.dart';
import '../../widgets/bottom_navigation.dart';

class _ProductSummary {
  final String productName;
  final int salesCount; // Хэд удаа борлуулсан
  final int totalQuantity; // Нийт тоо ширхэг
  final double totalAmount; // Нийт дүн (₮)

  const _ProductSummary({
    required this.productName,
    required this.salesCount,
    required this.totalQuantity,
    required this.totalAmount,
  });
}

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key});

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

enum _Granularity { day, month, year }

class _PerformanceScreenState extends State<PerformanceScreen> {
  static const _dailyTargetKey = 'sales_daily_target';
  double _dailyTarget = 1000000;

  late DateTime _focusedDay;
  late DateTime _selectedDay;
  String _productQuery = '';
  _Granularity _granularity = _Granularity.day;

  /// Local calendar day for "today" (no time component).
  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  void _snapToToday() {
    final t = _today();
    _focusedDay = t;
    _selectedDay = t;
  }

  @override
  void initState() {
    super.initState();
    _snapToToday();
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
    switch (_granularity) {
      case _Granularity.year:
        return '${_focusedDay.year} он';
      case _Granularity.month:
        final dfMonth = DateFormat('yyyy-MMMM', 'mn_MN');
        return dfMonth.format(_selectedDay);
      case _Granularity.day:
        final dfDay = DateFormat('yyyy-MM-dd');
        return dfDay.format(_selectedDay);
    }
  }

  String _monthNameMn(int month) =>
      DateFormat('MMMM', 'mn_MN').format(DateTime(2020, month, 1));

  ({DateTime start, DateTime endExclusive}) _getRange() {
    switch (_granularity) {
      case _Granularity.year:
        final start = DateTime(_focusedDay.year, 1, 1);
        final end = DateTime(_focusedDay.year + 1, 1, 1);
        return (start: start, endExclusive: end);
      case _Granularity.month:
        final start = DateTime(_selectedDay.year, _selectedDay.month, 1);
        final end = DateTime(_selectedDay.year, _selectedDay.month + 1, 1);
        return (start: start, endExclusive: end);
      case _Granularity.day:
        final day =
            DateTime(_selectedDay.year, _selectedDay.month, _selectedDay.day);
        return (start: day, endExclusive: day.add(const Duration(days: 1)));
    }
  }

  double _monthTotalForYearGrid(
    SalesProvider salesProvider,
    int year,
    int month,
    String? salespersonName,
  ) {
    final name = salespersonName?.trim();
    if (name == null || name.isEmpty) return 0;
    final start = DateTime(year, month, 1);
    final end = DateTime(year, month + 1, 1);
    final list = salesProvider
        .getSalesByDateRange(start, end)
        .where((s) => s.salespersonName == name)
        .toList();
    return list.fold<double>(0, (sum, s) => sum + s.amount);
  }

  String _granularityDropdownValue() => switch (_granularity) {
        _Granularity.day => 'Day',
        _Granularity.month => 'Month',
        _Granularity.year => 'Year',
      };

  void _setGranularityFromDropdown(String? v) {
    final g = switch (v) {
      'Month' => _Granularity.month,
      'Year' => _Granularity.year,
      _ => _Granularity.day,
    };
    setState(() {
      _granularity = g;
      if (g == _Granularity.day) {
        // Жил/Сар горимоос ирэхэд 1 сарын 1-д «нас барсан» үлддэг тул өдөр сонговол өнөөдөр рүү шилжүүлнэ.
        _snapToToday();
      } else if (g == _Granularity.month) {
        _selectedDay = DateTime(_focusedDay.year, _focusedDay.month, 1);
      } else if (g == _Granularity.year) {
        _selectedDay = DateTime(_focusedDay.year, 1, 1);
        _focusedDay = DateTime(_focusedDay.year, 1, 1);
      }
    });
  }

  Widget _buildYearMonthGrid(
    SalesProvider salesProvider,
    String? salespersonName,
  ) {
    final y = _focusedDay.year;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: () => setState(() {
                _focusedDay = DateTime(y - 1, 1, 1);
                _selectedDay = _focusedDay;
              }),
              icon: const Icon(Icons.chevron_left, color: Colors.white),
            ),
            Text(
              '$y',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              onPressed: () => setState(() {
                _focusedDay = DateTime(y + 1, 1, 1);
                _selectedDay = _focusedDay;
              }),
              icon: const Icon(Icons.chevron_right, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.05,
          children: List.generate(12, (i) {
            final month = i + 1;
            final total = _monthTotalForYearGrid(
                salesProvider, y, month, salespersonName);
            final monthLabel = _monthNameMn(month);
            return Material(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() {
                  _granularity = _Granularity.month;
                  _selectedDay = DateTime(y, month, 1);
                  _focusedDay = DateTime(y, month, 1);
                }),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        monthLabel,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${total.toStringAsFixed(0)} ₮',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: total > 0
                              ? const Color(0xFFA78BFA)
                              : Colors.white38,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        Text(
          'Сар дээр дарвал тухайн сарын дэлгэрэнгүйг харна',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFF0F0F23), // Dark background like the image
      appBar: AppBar(
        title: const Text('Гүйцэтгэл'),
        backgroundColor: const Color(0xFF1A1A2E), // Dark purple header
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
      bottomNavigationBar: const BottomNavigationWidget(),
      body: Consumer2<SalesProvider, AuthProvider>(
        builder: (context, salesProvider, authProvider, _) {
          final range = _getRange();
          final meName = authProvider.user?.name.trim();
          final hasSelf = meName != null && meName.isNotEmpty;

          final allSalesInRange = salesProvider.getSalesByDateRange(
              range.start, range.endExclusive);
          final filteredSales = hasSelf
              ? allSalesInRange
                  .where((s) => s.salespersonName == meName)
                  .toList()
              : <Sales>[];

          final selectedTotal =
              filteredSales.fold<double>(0, (sum, s) => sum + s.amount);

          final target = _dailyTarget;
          final pct = target <= 0 ? 0.0 : (selectedTotal / target);

          // Build product summary: name, count (times sold), total amount
          final productSummary = _buildProductSummary(
            filteredSales,
            query: _productQuery,
          );
          final totalQty =
              productSummary.fold<int>(0, (sum, e) => sum + e.totalQuantity);

          // Products without price (amount = 0 or very small)
          final productsWithoutPrice =
              productSummary.where((p) => p.totalAmount <= 0.01).toList();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with gradient purple
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Statistics',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: DropdownButton<String>(
                              value: _granularityDropdownValue(),
                              underline: const SizedBox(),
                              dropdownColor: const Color(0xFF1A1A2E),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600),
                              items: const [
                                DropdownMenuItem(
                                    value: 'Day', child: Text('Өдөр')),
                                DropdownMenuItem(
                                    value: 'Month', child: Text('Сар')),
                                DropdownMenuItem(
                                    value: 'Year', child: Text('Бүх сар')),
                              ],
                              onChanged: _setGranularityFromDropdown,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        switch (_granularity) {
                          _Granularity.year => 'Жил: ${_formatRangeLabel()}',
                          _Granularity.month => 'Сар: ${_formatRangeLabel()}',
                          _Granularity.day => 'Өдөр: ${_formatRangeLabel()}',
                        },
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.9), fontSize: 16),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_granularity == _Granularity.year)
                        _buildYearMonthGrid(salesProvider, meName)
                      else
                        TableCalendar(
                          calendarStyle: const CalendarStyle(
                            defaultTextStyle: TextStyle(color: Colors.white),
                            weekendTextStyle: TextStyle(color: Colors.white70),
                            selectedDecoration: BoxDecoration(
                              color: Color(0xFF8B5CF6),
                              shape: BoxShape.circle,
                            ),
                            todayDecoration: BoxDecoration(
                              color: Color(0xFF6366F1),
                              shape: BoxShape.circle,
                            ),
                            outsideTextStyle: TextStyle(color: Colors.white30),
                          ),
                          headerStyle: HeaderStyle(
                            titleCentered: true,
                            formatButtonVisible: false,
                            titleTextStyle: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold),
                            leftChevronIcon: const Icon(Icons.chevron_left,
                                color: Colors.white),
                            rightChevronIcon: const Icon(Icons.chevron_right,
                                color: Colors.white),
                          ),
                          daysOfWeekStyle: const DaysOfWeekStyle(
                            weekdayStyle: TextStyle(color: Colors.white70),
                            weekendStyle: TextStyle(color: Colors.white70),
                          ),
                          firstDay: DateTime.utc(2020, 1, 1),
                          lastDay: DateTime.utc(2035, 12, 31),
                          focusedDay: _focusedDay,
                          selectedDayPredicate: (day) =>
                              day.year == _selectedDay.year &&
                              day.month == _selectedDay.month &&
                              day.day == _selectedDay.day,
                          calendarFormat: CalendarFormat.month,
                          availableCalendarFormats: const {
                            CalendarFormat.month: 'Month'
                          },
                          onDaySelected: (selectedDay, focusedDay) {
                            setState(() {
                              _selectedDay = _granularity == _Granularity.month
                                  ? DateTime(
                                      selectedDay.year, selectedDay.month, 1)
                                  : DateTime(selectedDay.year,
                                      selectedDay.month, selectedDay.day);
                              _focusedDay = DateTime(focusedDay.year,
                                  focusedDay.month, focusedDay.day);
                            });
                          },
                          onPageChanged: (focusedDay) {
                            setState(() {
                              _focusedDay = DateTime(focusedDay.year,
                                  focusedDay.month, focusedDay.day);
                              if (_granularity == _Granularity.month) {
                                _selectedDay = DateTime(
                                    focusedDay.year, focusedDay.month, 1);
                              }
                            });
                          },
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Зөвхөн одоо нэвтэрсэн хэрэглэгчийн гүйцэтгэл
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.person_pin_rounded,
                          color: Color(0xFF8B5CF6), size: 28),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Таны гүйцэтгэл',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (hasSelf) ...[
                              Text(
                                meName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                              if ((authProvider.user?.email ?? '')
                                  .trim()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  authProvider.user!.email,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.55),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ] else
                              Text(
                                'Профайл ачаалагдаагүй. Дахин нэвтэрнэ үү.',
                                style: TextStyle(
                                  color: Colors.amber.shade200,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Total Sales Card - Dark purple gradient
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF8B5CF6), Color(0xFF6366F1)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        switch (_granularity) {
                          _Granularity.year => 'Жилийн нийт дүн',
                          _Granularity.month => 'Сарын нийт дүн',
                          _Granularity.day => 'Өдрийн нийт дүн',
                        },
                        style: TextStyle(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${selectedTotal.toStringAsFixed(0)} ₮',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      _buildProgressRow(
                        title: 'Төлөвлөгөө',
                        current: selectedTotal,
                        target: target,
                        progress: pct,
                        color: Colors.white,
                        isDark: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Products by name - Dark card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Барааны нэрээр бүлэглэсэн',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18),
                            ),
                          ),
                          Text(
                            _formatRangeLabel(),
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontWeight: FontWeight.w700,
                                fontSize: 12),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Нийт: $totalQty ширхэг',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.8),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14),
                            ),
                          ),
                          Text(
                            '${selectedTotal.toStringAsFixed(0)} ₮',
                            style: const TextStyle(
                                color: Color(0xFF8B5CF6),
                                fontWeight: FontWeight.w900,
                                fontSize: 16),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Барааны нэрээр хайх',
                          hintStyle:
                              TextStyle(color: Colors.white.withOpacity(0.5)),
                          prefixIcon: const Icon(Icons.search_rounded,
                              color: Color(0xFF8B5CF6)),
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white.withOpacity(0.1),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.2)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                                color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                                color: Color(0xFF8B5CF6), width: 2),
                          ),
                          suffixIcon: _productQuery.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Цэвэрлэх',
                                  onPressed: () =>
                                      setState(() => _productQuery = ''),
                                  icon: const Icon(Icons.close_rounded,
                                      color: Colors.white70),
                                ),
                        ),
                        onChanged: (v) => setState(() => _productQuery = v),
                      ),
                      const SizedBox(height: 16),
                      if (productSummary.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            _productQuery.isEmpty
                                ? 'Энэ хугацаанд борлуулалт алга.'
                                : 'Хайлтад таарах бараа олдсонгүй.',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.6),
                                fontWeight: FontWeight.w600),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: productSummary.length,
                          separatorBuilder: (_, __) => Divider(
                              height: 16, color: Colors.white.withOpacity(0.1)),
                          itemBuilder: (context, i) {
                            final item = productSummary[i];
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.05),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item.productName,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 15),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${item.salesCount} удаа борлуулсан',
                                          style: TextStyle(
                                            color:
                                                Colors.white.withOpacity(0.7),
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF8B5CF6)
                                              .withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '${item.totalQuantity} ширхэг',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF8B5CF6),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        '${item.totalAmount.toStringAsFixed(0)} ₮',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                          color: Color(0xFF8B5CF6),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),

                // Төлбөргүй бараа - Dark card with orange accent
                if (productsWithoutPrice.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: Colors.orange.shade400, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Төлбөргүй бараа',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: productsWithoutPrice.length,
                          separatorBuilder: (_, __) => Divider(
                              height: 12, color: Colors.white.withOpacity(0.1)),
                          itemBuilder: (context, i) {
                            final item = productsWithoutPrice[i];
                            return Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.orange.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.productName,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  Text(
                                    '${item.salesCount} удаа',
                                    style: TextStyle(
                                      color: Colors.orange.shade400,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  List<_ProductSummary> _buildProductSummary(
    List<dynamic> salesInRange, {
    required String query,
  }) {
    final q = query.trim().toLowerCase();
    final Map<String, _ProductSummary> summary = {};

    for (final s in salesInRange) {
      final String name = (s.productName as String?)?.trim().isNotEmpty == true
          ? (s.productName as String).trim()
          : 'Тодорхойгүй';
      if (q.isNotEmpty && !name.toLowerCase().contains(q)) continue;

      final int qty = (s.quantity as int?) ?? 1;
      final double amount = (s.amount as num?)?.toDouble() ?? 0.0;

      if (summary.containsKey(name)) {
        final existing = summary[name]!;
        summary[name] = _ProductSummary(
          productName: name,
          salesCount: existing.salesCount + 1,
          totalQuantity: existing.totalQuantity + qty,
          totalAmount: existing.totalAmount + amount,
        );
      } else {
        summary[name] = _ProductSummary(
          productName: name,
          salesCount: 1,
          totalQuantity: qty,
          totalAmount: amount,
        );
      }
    }

    final list = summary.values.toList();
    list.sort((a, b) => b.totalAmount
        .compareTo(a.totalAmount)); // Sort by total amount descending
    return list;
  }

  Widget _buildProgressRow({
    required String title,
    required double current,
    required double target,
    required double progress,
    required Color color,
    bool isDark = false,
  }) {
    final pct = (progress * 100).clamp(0, 999).toStringAsFixed(0);
    final capped = progress.clamp(0.0, 1.0);
    final textColor = isDark ? Colors.white : const Color(0xFF1E293B);
    final subTextColor =
        isDark ? Colors.white.withOpacity(0.7) : Colors.grey.shade600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(title,
                    style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13))),
            Text('$pct%',
                style: TextStyle(
                    fontWeight: FontWeight.w900, color: color, fontSize: 14)),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: capped,
            minHeight: 8,
            backgroundColor: isDark
                ? Colors.white.withOpacity(0.2)
                : color.withOpacity(0.12),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${current.toStringAsFixed(0)} ₮ / ${target.toStringAsFixed(0)} ₮',
          style: TextStyle(
              color: subTextColor, fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ],
    );
  }
}
