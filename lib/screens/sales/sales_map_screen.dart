import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/sales_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/order_model.dart';
import '../../models/sales_model.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/go_pop_scope.dart';
import '../../utils/order_schedule_utils.dart';

/// Нэг backend захиалга / нэг минутын legacy борлуулалтыг нэг цэг дээр нэгтгэнэ.
List<List<Sales>> clusterSalesForMap(List<Sales> sales) {
  final withOrder = <int, List<Sales>>{};
  final legacy = <String, List<Sales>>{};

  for (final s in sales) {
    final oid = s.warehouseOrderId;
    if (oid != null) {
      withOrder.putIfAbsent(oid, () => []).add(s);
    } else {
      final t = s.saleDate;
      final bucket = DateTime(t.year, t.month, t.day, t.hour, t.minute);
      final key =
          '${s.location}|${s.latitude}|${s.longitude}|${bucket.millisecondsSinceEpoch}';
      legacy.putIfAbsent(key, () => []).add(s);
    }
  }

  final out = <List<Sales>>[];
  for (final g in withOrder.values) {
    g.sort((a, b) => a.saleDate.compareTo(b.saleDate));
    out.add(g);
  }
  for (final g in legacy.values) {
    g.sort((a, b) => a.saleDate.compareTo(b.saleDate));
    out.add(g);
  }
  return out;
}

class SalesMapScreen extends StatefulWidget {
  const SalesMapScreen({super.key});

  @override
  State<SalesMapScreen> createState() => _SalesMapScreenState();
}

class _SalesMapScreenState extends State<SalesMapScreen> {
  static const LatLng _kUlaanbaatar = LatLng(47.9184, 106.9177);
  final MapController _mapController = MapController();

  List<Sales>? _selectedCluster;
  late DateTime _selectedDate;
  bool _moveToFirstOnNextBuild = false;
  bool _hasLoadedOrders = false;
  bool _syncingHistoryToWeve = false;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateUtils.dateOnly(DateTime.now());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadOrdersForSelectedDate();
    });
  }

  Future<void> _loadOrdersForSelectedDate() async {
    if (!mounted) return;
    final warehouseProvider =
        Provider.of<WarehouseProvider>(context, listen: false);
    if (!warehouseProvider.connected) return;
    final dayStart =
        DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final start = dayStart.subtract(const Duration(days: 7));
    final end = dayStart.add(const Duration(days: 7));
    await Provider.of<OrderProvider>(context, listen: false).fetchOrders(
      warehouseProvider.dio,
      startDate: start,
      endDate: end,
    );
    if (mounted) setState(() => _hasLoadedOrders = true);
  }

  bool _hasValidCoords(Sales s) {
    final lat = s.latitude;
    final lng = s.longitude;
    if (lat == null || lng == null) return false;
    if (lat == 0 && lng == 0) return false;
    return true;
  }

  bool _isSameLocalCalendarDay(DateTime a, DateTime selectedDay) {
    final aa = a.toLocal();
    return aa.year == selectedDay.year &&
        aa.month == selectedDay.month &&
        aa.day == selectedDay.day;
  }

  List<Order> _ordersForSelectedDay(List<Order> all, {required String role}) {
    return all
        .where((o) => _isSameLocalCalendarDay(
              OrderScheduleUtils.effectiveOrderCalendarDay(o, role: role),
              _selectedDate,
            ))
        .toList();
  }

  /// Зөвхөн одоогийн нэвтэрсэн борлуулагчийн захиалга (бусдын захиалга map дээр холилдохгүй).
  bool _isCurrentUsersAgent({
    required String? salespersonId,
    required String? authUserId,
    required int? agentId,
  }) {
    final sp = (salespersonId ?? '').trim();
    if (sp.isEmpty) return false;
    final uid = (authUserId ?? '').trim();
    if (uid.isNotEmpty && sp == uid) return true;
    if (agentId != null && sp == agentId.toString()) return true;
    // Fallback: if we can't reliably identify current user/agent,
    // don't hide points (otherwise map looks "empty" even though orders exist).
    if (uid.isEmpty && agentId == null) return true;
    return false;
  }

  Color _colorForSale(Sales sale) {
    final pm = (sale.paymentMethod ?? '').toLowerCase();
    if (pm.contains('зээл')) {
      return Colors.purple;
    }
    if (pm.contains('данс')) {
      return Colors.lightBlue;
    }
    return const Color(0xFF10B981);
  }

  int _totalPieces(List<Sales> group) {
    return group.fold<int>(0, (sum, s) => sum + (s.quantity ?? 1));
  }

  double _totalAmount(List<Sales> group) {
    return group.fold<double>(0.0, (sum, s) => sum + s.amount);
  }

  String _formatDate(BuildContext context, DateTime d) {
    return MaterialLocalizations.of(context).formatMediumDate(d);
  }

  Future<void> _syncLocationHistoryToWeve(BuildContext context) async {
    if (_syncingHistoryToWeve) return;
    final warehouse = Provider.of<WarehouseProvider>(context, listen: false);
    if (!warehouse.connected) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Weve/backend-тэй холбогдсон байх шаардлагатай.'),
        ),
      );
      return;
    }

    setState(() => _syncingHistoryToWeve = true);
    try {
      final locationProvider =
          Provider.of<LocationProvider>(context, listen: false);
      final r = await locationProvider.syncLocationHistoryToWeveBackend();
      if (!context.mounted) return;
      final ok = r['ok'] ?? 0;
      final fail = r['fail'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok == 0 && fail == 0
                ? 'Илгээх байршлын түүх байхгүй эсвэл agent/token тохируулаагүй байна.'
                : 'Weve руу илгээгдлээ: $ok цэг. Алдаа: $fail',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _syncingHistoryToWeve = false);
    }
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
      _selectedCluster = null;
      _moveToFirstOnNextBuild = true;
    });
    await _loadOrdersForSelectedDate();
  }

  @override
  Widget build(BuildContext context) {
    return GoPopScope(
      fallbackRoute: '/sales-dashboard',
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Борлуулалтын газрын зураг'),
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Буцах',
          onPressed: () {
            final router = GoRouter.of(context);
            if (router.canPop()) {
              context.pop();
            } else {
              context.go('/sales-dashboard');
            }
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              icon: _syncingHistoryToWeve
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.cloud_upload_rounded),
              tooltip: 'Байршлын түүхийг Weve/backend руу илгээх',
              onPressed: _syncingHistoryToWeve
                  ? null
                  : () => _syncLocationHistoryToWeve(context),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              icon: const Icon(Icons.calendar_month_rounded),
              tooltip: 'Огноо: ${_formatDate(context, _selectedDate)}',
              onPressed: _pickDate,
            ),
          ),
        ],
      ),
      body: Consumer4<SalesProvider, OrderProvider, LocationProvider,
          AuthProvider>(
        builder: (context, salesProvider, orderProvider, locationProvider,
            authProvider, child) {
          final authUserId = authProvider.user?.id;
          final agentId = locationProvider.currentAgentId;

          // 1) Sales records that already have coords — зөвхөн энэ хэрэглэгчийн бүртгэл
          final withCoords = salesProvider.sales
              .where(_hasValidCoords)
              .where((s) => _isSameLocalCalendarDay(s.saleDate, _selectedDate))
              .where(
                (s) => _isCurrentUsersAgent(
                  salespersonId: s.salespersonId,
                  authUserId: authUserId,
                  agentId: agentId,
                ),
              )
              .toList();

          // Эдгээр orderId-уудыг аль хэдийн локал Sales-ээр харуулж байгаа —
          // backend-аас үүсгэх orderSales-тэй нэгтгэвэл ижил бараа 2 удаа гарна.
          final orderIdsFromLocalSales = withCoords
              .map((s) => s.warehouseOrderId)
              .whereType<int>()
              .toSet();

          // 2) Orders (backend) → зөвхөн локал Sales байхгүй захиалгад л pin (хадгалсан байршилтай)
          final orderSales = <Sales>[];
          final role = authProvider.userRole;
          final selectedOrders =
              _ordersForSelectedDay(orderProvider.orders, role: role)
              .where(
                (o) => _isCurrentUsersAgent(
                  salespersonId: o.salespersonId,
                  authUserId: authUserId,
                  agentId: agentId,
                ),
              )
              .toList();
          for (final o in selectedOrders) {
            final oid = int.tryParse(o.id);
            if (oid == null) continue;
            if (orderIdsFromLocalSales.contains(oid)) {
              continue;
            }
            final loc = locationProvider.getOrderLocationSync(oid);
            if (loc == null) continue;
            for (final item in o.items) {
              orderSales.add(
                Sales(
                  id: 'order_${o.id}_${item.productId}',
                  productName: item.productName,
                  location: o.customerName,
                  salespersonId: o.salespersonId,
                  salespersonName: o.salespersonName,
                  amount: item.totalPrice,
                  saleDate: o.orderDate,
                  paymentMethod: 'Order',
                  latitude: loc.latitude,
                  longitude: loc.longitude,
                  quantity: item.quantity,
                  notes: o.notes,
                  ipAddress: null,
                  warehouseOrderId: oid,
                ),
              );
            }
          }

          final clusters = clusterSalesForMap([...withCoords, ...orderSales]);

          final hasPoints = clusters.isNotEmpty;
          final firstSale = hasPoints ? clusters.first.first : null;
          final initialCenter = hasPoints
              ? LatLng(firstSale!.latitude!, firstSale.longitude!)
              : _kUlaanbaatar;
          final initialZoom = hasPoints ? 16.0 : 11.0;

          if (_moveToFirstOnNextBuild && hasPoints) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              try {
                _mapController.move(initialCenter, initialZoom);
              } catch (_) {}
              if (mounted) {
                setState(() => _moveToFirstOnNextBuild = false);
              }
            });
          } else if (_moveToFirstOnNextBuild && !hasPoints) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              setState(() => _moveToFirstOnNextBuild = false);
            });
          }

          final markers = <Marker>[];
          final circles = <CircleMarker>[];
          for (final group in clusters) {
            final sale = group.first;
            final pos = LatLng(sale.latitude!, sale.longitude!);
            final color = _colorForSale(sale);
            final n = group.length;

            circles.add(
              CircleMarker(
                point: pos,
                radius: 22,
                color: color.withValues(alpha: 0.14),
                borderColor: color,
                borderStrokeWidth: 1,
              ),
            );

            markers.add(
              Marker(
                point: pos,
                width: n > 1 ? 52 : 44,
                height: n > 1 ? 52 : 44,
                child: GestureDetector(
                  onTap: () => setState(() => _selectedCluster = group),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(
                        Icons.location_on,
                        size: n > 1 ? 44 : 40,
                        color: color,
                      ),
                      if (n > 1)
                        Positioned(
                          top: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$n',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }

          return Stack(
            children: [
              Positioned.fill(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: initialCenter,
                    initialZoom: initialZoom,
                    onTap: (_, __) => setState(() => _selectedCluster = null),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'aguulgav3',
                    ),
                    CircleLayer(circles: circles),
                    MarkerLayer(markers: markers),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: IgnorePointer(
                  ignoring: _selectedCluster != null,
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(
                        '${_formatDate(context, _selectedDate)} · ${clusters.length} цэг'
                        '${(!_hasLoadedOrders && clusters.isEmpty) ? ' (ачаалж байна...)' : ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (!hasPoints)
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: Material(
                    elevation: 2,
                    borderRadius: BorderRadius.circular(12),
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      child: Text(
                        'Байршилтай борлуулалт олдсонгүй. Борлуулалт бүртгэхэд GPS координат хадгалагдсан эсэхийг шалгана уу.',
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_selectedCluster != null && _selectedCluster!.isNotEmpty)
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Builder(
                    builder: (context) {
                      final g = _selectedCluster!;
                      final head = g.first;
                      final pieces = _totalPieces(g);
                      final total = _totalAmount(g);
                      final orderId = head.warehouseOrderId;

                      return Card(
                        elevation: 8,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        child: Container(
                          constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(context).size.height * 0.45,
                          ),
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981)
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.store,
                                        color: Color(0xFF10B981)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          head.location,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (orderId != null)
                                          Text(
                                            'Захиалга #$orderId · ${g.length} барааны мөр',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 12,
                                            ),
                                          )
                                        else
                                          Text(
                                            '${g.length} мөр (нэг удаагийн бүртгэл)',
                                            style: TextStyle(
                                              color: Colors.grey[600],
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${total.toStringAsFixed(0)} ₮',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF10B981),
                                        ),
                                      ),
                                      Text(
                                        'Нийт $pieces ширхэг',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[700],
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        '${head.saleDate.year}-${head.saleDate.month.toString().padLeft(2, '0')}-${head.saleDate.day.toString().padLeft(2, '0')} ${_formatTime(head.saleDate)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[500],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              Flexible(
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: g.length,
                                  itemBuilder: (context, index) {
                                    final sale = g[index];
                                    final q = sale.quantity ?? 1;
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 10.0),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  sale.productName,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w600),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '$q ширхэг — ${sale.amount.toStringAsFixed(0)} ₮',
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                              if (head.notes != null && head.notes!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[100],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      head.notes!,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
