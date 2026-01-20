import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/sales_provider.dart';
import '../../models/sales_model.dart';
import 'package:go_router/go_router.dart';

class SalesMapScreen extends StatefulWidget {
  const SalesMapScreen({super.key});

  @override
  State<SalesMapScreen> createState() => _SalesMapScreenState();
}

class _SalesMapScreenState extends State<SalesMapScreen> {
  final MapController _mapController = MapController();
  Sales? _selectedSale;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Map'),
        backgroundColor: const Color(0xFF10B981),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Consumer<SalesProvider>(
        builder: (context, salesProvider, child) {
          final salesWithLocation = salesProvider.sales.where((s) => s.latitude != null && s.longitude != null).toList();

          if (salesWithLocation.isEmpty) {
            return const Center(
              child: Text('No sales with location data found.'),
            );
          }

          // Center map on the first sale or default to Ulaanbaatar
          final initialCenter = salesWithLocation.isNotEmpty
              ? LatLng(salesWithLocation.first.latitude!, salesWithLocation.first.longitude!)
              : const LatLng(47.9184, 106.9177);

          return Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: initialCenter,
                  initialZoom: 18.0, // Zoom in closer to see small radius
                  onTap: (_, __) {
                    setState(() {
                      _selectedSale = null;
                    });
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.app',
                  ),
                  CircleLayer(
                    circles: salesWithLocation.map((sale) {
                      return CircleMarker(
                        point: LatLng(sale.latitude!, sale.longitude!),
                        radius: 2, // 2 meters radius (in meters if useRadiusInMeter is true)
                        useRadiusInMeter: true,
                        color: const Color(0xFF10B981).withOpacity(0.3),
                        borderColor: const Color(0xFF10B981),
                        borderStrokeWidth: 1,
                      );
                    }).toList(),
                  ),
                  MarkerLayer(
                    markers: salesWithLocation.map((sale) {
                      return Marker(
                        point: LatLng(sale.latitude!, sale.longitude!),
                        width: 40,
                        height: 40,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedSale = sale;
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.shopping_cart,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              if (_selectedSale != null)
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Builder(
                    builder: (context) {
                      // Find all sales for this location (shop)
                      final shopSales = salesProvider.sales.where((s) => s.location == _selectedSale!.location).toList();
                      final totalAmount = shopSales.fold(0.0, (sum, s) => sum + s.amount);
                      
                      return Card(
                        elevation: 8,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Container(
                          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.4),
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
                                      color: const Color(0xFF10B981).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.store, color: Color(0xFF10B981)),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _selectedSale!.location,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          'Нийт: ${shopSales.length} бараа',
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
                                        '\$${totalAmount.toStringAsFixed(0)}',
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF10B981),
                                        ),
                                      ),
                                      Text(
                                        '${_selectedSale!.saleDate.year}-${_selectedSale!.saleDate.month.toString().padLeft(2, '0')}-${_selectedSale!.saleDate.day.toString().padLeft(2, '0')} ${_formatDate(_selectedSale!.saleDate)}',
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
                                  itemCount: shopSales.length,
                                  itemBuilder: (context, index) {
                                    final sale = shopSales[index];
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8.0),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  sale.productName,
                                                  style: const TextStyle(fontWeight: FontWeight.w500),
                                                ),
                                                Text(
                                                  '${sale.quantity ?? 1} x ${sale.amount.toStringAsFixed(0)} ₮',
                                                  style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            '${sale.amount.toStringAsFixed(0)} ₮',
                                            style: const TextStyle(fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                              if (_selectedSale!.notes != null && _selectedSale!.notes!.isNotEmpty) ...[
                                 const SizedBox(height: 12),
                                 Container(
                                   padding: const EdgeInsets.all(8),
                                   width: double.infinity,
                                   decoration: BoxDecoration(
                                     color: Colors.grey[100],
                                     borderRadius: BorderRadius.circular(8),
                                   ),
                                   child: Text(
                                     _selectedSale!.notes!,
                                     style: const TextStyle(fontSize: 13),
                                   ),
                                 ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  String _formatDate(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

