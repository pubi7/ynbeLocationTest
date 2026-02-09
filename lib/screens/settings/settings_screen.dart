import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../providers/mobileUserLogin.dart';
import '../../providers/location_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/shop_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../config/platform_info.dart';
import '../../widgets/hamburger_menu.dart';
import '../../services/bluetooth_printer_service.dart';
import '../../widgets/bluetooth_printer_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;
  bool _newSettingEnabled = false; // New boolean for the additional setting
  // Language & Region section removed

  // Sales targets (used for % progress on dashboard)
  static const _dailyTargetKey = 'sales_daily_target';
  final _dailyTargetController = TextEditingController();
  double _dailyTarget = 1000000; // default 1,000,000₮

  // Warehouse web connection
  static const _warehouseApiBaseUrlKey = 'warehouse_api_base_url';
  final _warehouseApiBaseUrlController = TextEditingController(
      text: PlatformInfo.isAndroid
          ? 'http://192.168.1.6:3000' // Use PC IP for physical devices
          : 'http://192.168.1.6:3000'); // Use PC IP instead of localhost
  final _warehouseEmailController =
      TextEditingController(text: 'agent@oasis.mn');
  final _warehousePasswordController = TextEditingController(text: 'agent123');

  @override
  void initState() {
    super.initState();
    _loadTargets();
    _loadWarehouseApiBaseUrl();
    // Refresh profile when screen loads if connected
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshProfileIfConnected();
    });
  }

  Future<void> _refreshProfileIfConnected() async {
    final warehouseProvider =
        Provider.of<WarehouseProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    if (warehouseProvider.connected) {
      try {
        await warehouseProvider.refreshProfile(authProvider);
      } catch (e) {
        debugPrint('Failed to refresh profile on init: $e');
      }
    }
  }

  @override
  void dispose() {
    _warehouseApiBaseUrlController.dispose();
    _warehouseEmailController.dispose();
    _warehousePasswordController.dispose();
    _dailyTargetController.dispose();
    super.dispose();
  }

  Future<void> _loadWarehouseApiBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getString(_warehouseApiBaseUrlKey);
    if (!mounted) return;
    if (v != null && v.trim().isNotEmpty) {
      setState(() {
        _warehouseApiBaseUrlController.text = v.trim();
      });
    }
  }

  Future<void> _saveWarehouseApiBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_warehouseApiBaseUrlKey, value.trim());
  }

  Future<void> _loadTargets() async {
    final prefs = await SharedPreferences.getInstance();
    final d = prefs.getDouble(_dailyTargetKey);
    if (!mounted) return;
    setState(() {
      _dailyTarget = d ?? _dailyTarget;
      _dailyTargetController.text = _dailyTarget.toStringAsFixed(0);
    });
  }

  Future<void> _saveTargets() async {
    final d =
        double.tryParse(_dailyTargetController.text.replaceAll(',', '').trim());
    if (d == null || d <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Төлөвлөгөөний дүн буруу байна'),
            backgroundColor: Colors.red),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_dailyTargetKey, d);
    if (!mounted) return;
    setState(() {
      _dailyTarget = d;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Төлөвлөгөө хадгаллаа'), backgroundColor: Colors.green),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Settings'),
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
      body: SingleChildScrollView(
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
                    Color(0xFF6366F1),
                    Color(0xFF8B5CF6),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.settings_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Settings',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Customize your app experience',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // User Profile Section
            _buildSectionCard(
              'Profile',
              Icons.person_rounded,
              const Color(0xFF3B82F6),
              [
                _buildProfileTile(),
              ],
            ),
            const SizedBox(height: 20),

            // Warehouse Web Sync (read-only: fetch products/shops only)
            _buildSectionCard(
              'Warehouse Web Sync',
              Icons.cloud_sync_rounded,
              const Color(0xFF6366F1),
              [
                Consumer3<WarehouseProvider, ProductProvider, ShopProvider>(
                  builder: (context, warehouseProvider, productProvider,
                      shopProvider, _) {
                    final authProvider =
                        Provider.of<AuthProvider>(context, listen: false);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 4),
                          leading: Icon(
                            warehouseProvider.connected
                                ? Icons.check_circle_rounded
                                : Icons.cloud_off_rounded,
                            color: warehouseProvider.connected
                                ? const Color(0xFF10B981)
                                : Colors.grey[600],
                          ),
                          title: Text(
                            warehouseProvider.connected
                                ? 'Connected (read-only)'
                                : 'Not connected',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'API: ${warehouseProvider.apiBaseUrl}\n'
                            'Products: ${productProvider.products.length} | Shops: ${shopProvider.shops.length}',
                          ),
                          trailing: warehouseProvider.connected
                              ? TextButton(
                                  onPressed: warehouseProvider.isLoading
                                      ? null
                                      : () async {
                                          await warehouseProvider.disconnect();
                                          productProvider.setProducts(const []);
                                          shopProvider.setShops(const []);
                                        },
                                  child: const Text('Disconnect'),
                                )
                              : null,
                        ),
                        if (!warehouseProvider.connected) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _warehouseApiBaseUrlController,
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Server URL (ж: http://192.168.1.6:3000)',
                                    helperText:
                                        'Android emulator: http://10.0.2.2:3000 • Phone: PC IP:3000',
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: warehouseProvider.isLoading
                                        ? null
                                        : () async {
                                            final v =
                                                _warehouseApiBaseUrlController
                                                    .text
                                                    .trim();
                                            await _saveWarehouseApiBaseUrl(v);
                                            await warehouseProvider
                                                .updateApiBaseUrl(v);
                                          },
                                    child: const Text('Save Server URL'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          if ((warehouseProvider.error ?? '').isNotEmpty) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 20),
                              child: Text(
                                'Error: ${warehouseProvider.error}',
                                style: const TextStyle(color: Colors.red),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              children: [
                                TextField(
                                  controller: _warehouseEmailController,
                                  decoration: const InputDecoration(
                                      labelText: 'Warehouse Email'),
                                ),
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _warehousePasswordController,
                                  obscureText: true,
                                  decoration: const InputDecoration(
                                      labelText: 'Warehouse Password'),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: warehouseProvider.isLoading
                                        ? null
                                        : () async {
                                            final ok =
                                                await warehouseProvider.connect(
                                              identifier:
                                                  _warehouseEmailController.text
                                                      .trim(),
                                              password:
                                                  _warehousePasswordController
                                                      .text,
                                              authProvider: authProvider,
                                            );
                                            if (ok) {
                                              // Add delays between requests to prevent rate limiting
                                              // Refresh profile after successful connection
                                              try {
                                                await Future.delayed(
                                                    const Duration(
                                                        milliseconds: 500));
                                                await warehouseProvider
                                                    .refreshProfile(
                                                        authProvider);
                                              } catch (e) {
                                                debugPrint(
                                                    'Failed to refresh profile: $e');
                                              }

                                              // Add delay before fetching products
                                              await Future.delayed(
                                                  const Duration(
                                                      milliseconds: 500));
                                              try {
                                                await warehouseProvider
                                                    .refreshProducts();
                                              } catch (e) {
                                                debugPrint(
                                                    'Failed to refresh products: $e');
                                              }

                                              // Update products immediately after refresh
                                              productProvider.setProducts(
                                                  warehouseProvider.products);
                                              debugPrint(
                                                  '✅ Products synced: ${warehouseProvider.products.length}');

                                              // Add delay before fetching shops
                                              await Future.delayed(
                                                  const Duration(
                                                      milliseconds: 500));
                                              try {
                                                await warehouseProvider
                                                    .refreshShops(
                                                        authProvider:
                                                            authProvider);
                                                // Update shops immediately after refresh
                                                shopProvider.setShops(
                                                    warehouseProvider.shops);
                                                debugPrint(
                                                    '✅ Shops synced: ${warehouseProvider.shops.length}');
                                              } catch (e) {
                                                debugPrint(
                                                    '❌ Failed to refresh shops: $e');
                                                // Still update with whatever we have
                                                shopProvider.setShops(
                                                    warehouseProvider.shops);
                                              }
                                            }
                                          },
                                    child: warehouseProvider.isLoading
                                        ? const Text('Connecting...')
                                        : const Text('Connect & Sync'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: warehouseProvider.isLoading
                                    ? null
                                    : () async {
                                        // Refresh products first
                                        try {
                                          await warehouseProvider
                                              .refreshProducts();
                                          // Update products immediately after refresh
                                          productProvider.setProducts(
                                              warehouseProvider.products);
                                          debugPrint(
                                              '✅ Products synced: ${warehouseProvider.products.length}');
                                        } catch (e) {
                                          debugPrint(
                                              '❌ Failed to refresh products: $e');
                                          // Still update with whatever we have
                                          productProvider.setProducts(
                                              warehouseProvider.products);
                                        }

                                        // Add delay before fetching shops to prevent rate limiting
                                        await Future.delayed(
                                            const Duration(milliseconds: 500));

                                        // Refresh shops second
                                        try {
                                          await warehouseProvider.refreshShops(
                                              authProvider: authProvider);
                                          // Update shops immediately after refresh
                                          shopProvider.setShops(
                                              warehouseProvider.shops);
                                          debugPrint(
                                              '✅ Shops synced: ${warehouseProvider.shops.length}');
                                        } catch (e) {
                                          debugPrint(
                                              '❌ Failed to refresh shops: $e');
                                          // Still update with whatever we have
                                          shopProvider.setShops(
                                              warehouseProvider.shops);
                                        }
                                      },
                                child: warehouseProvider.isLoading
                                    ? const Text('Syncing...')
                                    : const Text('Sync now'),
                              ),
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Orders Section
            _buildSectionCard(
              'Orders',
              Icons.shopping_cart_rounded,
              const Color(0xFF3B82F6),
              [
                Consumer<OrderProvider>(
                  builder: (context, orderProvider, child) {
                    final totalOrders = orderProvider.orders.length;
                    final totalValue = orderProvider.orders
                        .fold(0.0, (sum, order) => sum + order.totalAmount);
                    final pendingOrders = orderProvider.orders
                        .where(
                            (order) => order.status.toLowerCase() == 'pending')
                        .length;

                    return Column(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          leading: Icon(Icons.shopping_cart_rounded,
                              color: Colors.grey[600]),
                          title: const Text(
                            'Нийт захиалга',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Text(
                            '$totalOrders захиалга',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                          trailing: Text(
                            '\$${totalValue.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Color(0xFF3B82F6),
                            ),
                          ),
                        ),
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 4),
                          leading: Icon(Icons.pending_actions_rounded,
                              color: Colors.grey[600]),
                          title: const Text(
                            'Хүлээгдэж буй',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Text(
                            '$pendingOrders захиалга',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded,
                              color: Colors.grey),
                          onTap: () => context.go('/sales-orders'),
                        ),
                        _buildActionTile(
                          'Бүх захиалга харах',
                          'Захиалгын дэлгэрэнгүй мэдээлэл',
                          Icons.list_rounded,
                          () => context.go('/sales-orders'),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // App Preferences Section
            _buildSectionCard(
              'App Preferences',
              Icons.tune_rounded,
              const Color(0xFF10B981),
              [
                _buildSwitchTile(
                  'Notifications',
                  'Receive push notifications',
                  Icons.notifications_rounded,
                  _notificationsEnabled,
                  (value) => setState(() => _notificationsEnabled = value),
                ),
                _buildSwitchTile(
                  'Dark Mode',
                  'Use dark theme',
                  Icons.dark_mode_rounded,
                  _darkModeEnabled,
                  (value) => setState(() => _darkModeEnabled = value),
                ),
                // IP Only Mode Tile
                Consumer<LocationProvider>(
                  builder: (context, locationProvider, child) {
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                      leading:
                          Icon(Icons.wifi_rounded, color: Colors.grey[600]),
                      title: const Text(
                        'Зөвхөн IP хаягаар байршил тодорхойлох',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: const Text(
                        'GPS унтрааж, зөвхөн IP хаягаар байршлыг тодорхойлох',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 14,
                        ),
                      ),
                      trailing: Switch(
                        value: locationProvider.useIpOnlyMode,
                        onChanged: (value) {
                          locationProvider.setIpOnlyMode(value);
                        },
                        activeColor: const Color(0xFF3B82F6),
                      ),
                    );
                  },
                ),
                // New Setting Tile
                _buildSwitchTile(
                  'New Setting',
                  'Description of the new setting',
                  Icons.new_releases_rounded,
                  _newSettingEnabled,
                  (value) => setState(() => _newSettingEnabled = value),
                ),
                // Sales targets used for dashboard % completion
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  leading: Icon(Icons.flag_rounded, color: Colors.grey[600]),
                  title: const Text(
                    'Өдрийн төлөвлөгөө (₮)',
                    style: TextStyle(fontWeight: FontWeight.w500, fontSize: 16),
                  ),
                  subtitle: TextField(
                    controller: _dailyTargetController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'Ж: 1000000',
                      border: InputBorder.none,
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _saveTargets,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Төлөвлөгөө хадгалах'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Bluetooth Printer Section
            _buildSectionCard(
              'Bluetooth Принтер',
              Icons.print_rounded,
              const Color(0xFF3B82F6),
              [
                Builder(
                  builder: (context) {
                    final btPrinter = BluetoothPrinterService();
                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      leading: Icon(
                        btPrinter.isConnected
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth,
                        color: btPrinter.isConnected
                            ? Colors.green
                            : Colors.grey[600],
                      ),
                      title: Text(
                        btPrinter.isConnected
                            ? btPrinter.connectedPrinterName ?? 'Принтер холбоотой'
                            : 'Принтер холбоогүй',
                        style: const TextStyle(
                            fontWeight: FontWeight.w500, fontSize: 16),
                      ),
                      subtitle: Text(
                        btPrinter.isConnected
                            ? 'Холбогдсон ✅'
                            : 'Bluetooth принтер сонгоно уу',
                        style: TextStyle(
                          color: btPrinter.isConnected
                              ? Colors.green
                              : Colors.grey[500],
                        ),
                      ),
                      trailing: ElevatedButton(
                        onPressed: () async {
                          await BluetoothPrinterDialog.show(context);
                          setState(() {}); // Refresh UI
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF3B82F6),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          btPrinter.isConnected ? 'Солих' : 'Холбох',
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Data & Privacy Section
            _buildSectionCard(
              'Data & Privacy',
              Icons.security_rounded,
              const Color(0xFFF59E0B),
              [
                _buildActionTile(
                  'Export Data',
                  'Download your data',
                  Icons.download_rounded,
                  () => _showExportDialog(),
                ),
                _buildActionTile(
                  'Clear Cache',
                  'Free up storage space',
                  Icons.cleaning_services_rounded,
                  () => _showClearCacheDialog(),
                ),
                _buildActionTile(
                  'Privacy Policy',
                  'View our privacy policy',
                  Icons.privacy_tip_rounded,
                  () => _showPrivacyDialog(),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Logout Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showLogoutDialog(),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Logout'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(
      String title, IconData icon, Color color, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildProfileTile() {
    return Consumer2<AuthProvider, WarehouseProvider>(
      builder: (context, authProvider, warehouseProvider, child) {
        // Get display name - prefer displayName from backend, fallback to name
        final displayName = authProvider.user?.name ?? 'User';
        final roleDisplay = (authProvider.user?.role ?? 'user').toUpperCase();

        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF3B82F6).withOpacity(0.1),
            child: Icon(
              Icons.person_rounded,
              color: const Color(0xFF3B82F6),
            ),
          ),
          title: Text(
            displayName,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                roleDisplay,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 14,
                ),
              ),
              if (warehouseProvider.connected &&
                  authProvider.user?.email != null)
                Text(
                  authProvider.user!.email!,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => _showEditProfileDialog(),
          ),
        );
      },
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, IconData icon,
      bool value, Function(bool) onChanged) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: Colors.grey[600]),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 14,
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: const Color(0xFF10B981),
      ),
    );
  }

  // Dropdown section removed

  Widget _buildActionTile(
      String title, String subtitle, IconData icon, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: Colors.grey[600]),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 16,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: Colors.grey[600],
          fontSize: 14,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      onTap: onTap,
    );
  }

  void _showEditProfileDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Profile'),
        content: const Text(
            'Profile editing functionality would be implemented here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showExportDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Data'),
        content: const Text(
            'Your data will be exported and sent to your email address.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Data export initiated')),
              );
            },
            child: const Text('Export'),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text(
            'This will clear all cached data and free up storage space.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache cleared successfully')),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Privacy Policy'),
        content: const SingleChildScrollView(
          child: Text(
            'This app collects and processes your data in accordance with our privacy policy. We are committed to protecting your privacy and ensuring the security of your personal information.',
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

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final loginProvider =
                  Provider.of<MobileUserLoginProvider>(context, listen: false);
              final authProvider =
                  Provider.of<AuthProvider>(context, listen: false);
              await loginProvider.logout();
              await authProvider.logout();
              if (context.mounted) {
                context.go('/login');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  // Map dialog removed (this settings section only keeps IP-only toggle).
}

class _MapDialog extends StatefulWidget {
  final LocationProvider locationProvider;
  final List<Map<String, dynamic>> shops;

  const _MapDialog({
    required this.locationProvider,
    required this.shops,
  });

  @override
  State<_MapDialog> createState() => _MapDialogState();
}

class _MapDialogState extends State<_MapDialog> {
  final MapController _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  /// Generate circle points for a given center and radius in meters
  List<latlong.LatLng> _generateCirclePoints(
      latlong.LatLng center, double radiusInMeters) {
    const int points = 64; // Number of points to create a smooth circle
    List<latlong.LatLng> circlePoints = [];

    // Use latlong2 Distance utility for accurate calculations
    final distance = latlong.Distance();

    for (int i = 0; i < points; i++) {
      // Calculate bearing in degrees (0-360)
      double bearing = (i * 360.0 / points);

      // Calculate point using offset in meters with bearing
      latlong.LatLng point = distance.offset(
        center,
        radiusInMeters,
        bearing,
      );

      circlePoints.add(point);
    }

    // Close the circle by adding the first point again
    if (circlePoints.isNotEmpty) {
      circlePoints.add(circlePoints.first);
    }

    return circlePoints;
  }

  Future<void> _refreshMap() async {
    setState(() {}); // Show loading state

    final locationProvider =
        Provider.of<LocationProvider>(context, listen: false);

    try {
      if (!locationProvider.isTracking) {
        await locationProvider.startTracking();
      } else {
        await locationProvider.updateCurrentLocation();
      }

      // Wait for location to update
      int attempts = 0;
      while (locationProvider.currentLocation == null && attempts < 10) {
        await Future.delayed(const Duration(milliseconds: 300));
        attempts++;
      }

      // Center map on new location after refresh
      final currentLoc = locationProvider.currentLocation;
      if (currentLoc != null) {
        final zoom =
            _mapController.camera.zoom > 0 ? _mapController.camera.zoom : 13.0;
        _mapController.move(
          latlong.LatLng(
            currentLoc.latitude,
            currentLoc.longitude,
          ),
          zoom,
        );
      }
    } catch (e) {
      print('Refresh map error: $e');
    }

    // Force map rebuild
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.8,
        width: MediaQuery.of(context).size.width * 0.95,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header with title and controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Байршил хянах',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Явсан маршрут болон дэлгүүрүүд',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.info_outline),
                      onPressed: () => _showMapLegend(),
                      tooltip: 'Тусламж',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Map Legend
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildLegendItem(
                      Icons.location_on, 'Одоо байгаа', Colors.blue),
                  _buildLegendItem(Icons.store, 'Дэлгүүр', Colors.green),
                  _buildLegendItem(Icons.warehouse, 'Агуулах', Colors.orange),
                  _buildLegendItem(Icons.timeline, 'Явсан зам', Colors.purple),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Real Map
            Expanded(
              child: Consumer<LocationProvider>(
                builder: (context, locationProvider, _) {
                  return Stack(
                    children: [
                      // OpenStreetMap
                      FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: locationProvider.currentLocation !=
                                  null
                              ? latlong.LatLng(
                                  locationProvider.currentLocation!.latitude,
                                  locationProvider.currentLocation!.longitude)
                              : const latlong.LatLng(
                                  47.9188, 106.9177), // УБ хот төв
                          initialZoom: 13.0,
                          minZoom: 5.0,
                          maxZoom: 18.0,
                          // Disable map interactions if tracking is not active
                          interactiveFlags: locationProvider.isTracking
                              ? InteractiveFlag.all
                              : InteractiveFlag.none,
                          onMapReady: () {
                            if (locationProvider.currentLocation != null) {
                              _mapController.move(
                                latlong.LatLng(
                                  locationProvider.currentLocation!.latitude,
                                  locationProvider.currentLocation!.longitude,
                                ),
                                13.0,
                              );
                            }
                          },
                        ),
                        children: [
                          // Primary tile layer - OpenStreetMap
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.aguulgav3',
                            maxZoom: 18,
                            additionalOptions: const {
                              'attribution': '© OpenStreetMap contributors',
                            },
                          ),

                          // Fallback tile layer - CartoDB
                          TileLayer(
                            urlTemplate:
                                'https://cartodb-basemaps-{s}.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png',
                            subdomains: const ['a', 'b', 'c', 'd'],
                            userAgentPackageName: 'com.example.aguulgav3',
                            maxZoom: 18,
                            additionalOptions: const {
                              'attribution': '© CartoDB',
                            },
                          ),

                          // Markers - GPS байршил үргэлж харагдана
                          MarkerLayer(
                            markers: [
                              // Current location marker (GPS байршил)
                              if (locationProvider.currentLocation != null)
                                Marker(
                                  point: latlong.LatLng(
                                      locationProvider
                                          .currentLocation!.latitude,
                                      locationProvider
                                          .currentLocation!.longitude),
                                  width: 50,
                                  height: 50,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white, width: 4),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.blue.withOpacity(0.5),
                                          blurRadius: 8,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.my_location,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ),

                              // Борлуулалтын байршлуудын marker-үүд (бүх борлуулалтын байршлуудыг харуулах)
                              ...widget.shops.map((sale) {
                                // Calculate distance for display (if current location available)
                                double distanceInMeters =
                                    locationProvider.currentLocation != null
                                        ? Geolocator.distanceBetween(
                                            locationProvider
                                                .currentLocation!.latitude,
                                            locationProvider
                                                .currentLocation!.longitude,
                                            sale['lat'],
                                            sale['lng'],
                                          )
                                        : 0.0;

                                // Төлбөрийн төрлөөр өнгө сонгох
                                Color markerColor;
                                IconData markerIcon;
                                final paymentMethod = sale['paymentMethod']
                                        ?.toString()
                                        .toLowerCase() ??
                                    'бэлэн';
                                if (paymentMethod.contains('зээл')) {
                                  markerColor = Colors.purple;
                                  markerIcon = Icons.credit_card;
                                } else if (paymentMethod.contains('данс')) {
                                  markerColor = Colors.blue;
                                  markerIcon = Icons.account_balance_wallet;
                                } else {
                                  markerColor = Colors.green;
                                  markerIcon = Icons.money;
                                }

                                return Marker(
                                  point:
                                      latlong.LatLng(sale['lat'], sale['lng']),
                                  width: 60,
                                  height: 80,
                                  child: GestureDetector(
                                    onTap: () {
                                      // Marker дээр дарахад мэдээлэл харуулах
                                      showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: Text(
                                              sale['name'] ?? 'Борлуулалт'),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                  'Дэлгүүр: ${sale['address'] ?? ''}'),
                                              const SizedBox(height: 8),
                                              if (sale['quantity'] != null)
                                                Text(
                                                    'Тоо хэмжээ: ${sale['quantity']} ширхэг'),
                                              if (sale['quantity'] != null)
                                                const SizedBox(height: 8),
                                              Text(
                                                  'Дүн: ${sale['amount']?.toStringAsFixed(0) ?? '0'} ₮'),
                                              const SizedBox(height: 8),
                                              Text(
                                                  'Төлбөрийн төрөл: ${sale['paymentMethod'] ?? 'бэлэн'}'),
                                              const SizedBox(height: 8),
                                              Text(
                                                  'Огноо: ${sale['date'] != null ? (sale['date'] as DateTime).toString().split('.')[0] : ''}'),
                                            ],
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context),
                                              child: const Text('Хаах'),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 6, vertical: 3),
                                          decoration: BoxDecoration(
                                            color:
                                                Colors.black.withOpacity(0.7),
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            locationProvider.currentLocation !=
                                                    null
                                                ? '${distanceInMeters.toStringAsFixed(0)}м'
                                                : sale['name']
                                                        ?.toString()
                                                        .substring(
                                                            0,
                                                            sale['name']
                                                                        .toString()
                                                                        .length >
                                                                    10
                                                                ? 10
                                                                : sale['name']
                                                                    .toString()
                                                                    .length) ??
                                                    'Борлуулалт',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Container(
                                          width: 40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: markerColor,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: Colors.white, width: 2),
                                          ),
                                          child: Icon(
                                            markerIcon,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ],
                          ),

                          // 20 meter radius circle around current GPS location
                          if (locationProvider.isTracking &&
                              locationProvider.currentLocation != null)
                            PolygonLayer(
                              polygons: [
                                Polygon(
                                  points: _generateCirclePoints(
                                    latlong.LatLng(
                                      locationProvider
                                          .currentLocation!.latitude,
                                      locationProvider
                                          .currentLocation!.longitude,
                                    ),
                                    20.0, // 20 meters radius
                                  ),
                                  color: Colors.blue.withOpacity(0.2),
                                  borderColor: Colors.blue.withOpacity(0.8),
                                  borderStrokeWidth: 2.0,
                                  isFilled: true,
                                ),
                              ],
                            ),

                          // Route polyline - Dynamic path showing actual traveled route
                          // The polyline connects all recorded location points in order, showing the actual path
                          if (locationProvider.isTracking &&
                              locationProvider.locationHistory.isNotEmpty)
                            PolylineLayer(
                              polylines: [
                                Polyline(
                                  points: locationProvider.locationHistory,
                                  color: const Color(0xFF6366F1),
                                  strokeWidth: 5.0,
                                  borderColor: Colors.white,
                                  borderStrokeWidth: 2.0,
                                ),
                              ],
                            ),

                          // Additional markers for each location point in history for better visualization
                          if (locationProvider.isTracking &&
                              locationProvider.locationHistory.length > 1)
                            MarkerLayer(
                              markers: [
                                // Add small markers for path points (every 5th point to avoid clutter)
                                ...locationProvider.locationHistory
                                    .asMap()
                                    .entries
                                    .where((entry) =>
                                        entry.key % 5 == 0) // Every 5th point
                                    .map((entry) {
                                  final point = entry.value;
                                  return Marker(
                                    point: latlong.LatLng(
                                        point.latitude, point.longitude),
                                    width: 8,
                                    height: 8,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6366F1)
                                            .withOpacity(0.6),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white, width: 1),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ],
                            ),
                        ],
                      ),

                      // Control buttons (refresh and my location)
                      Positioned(
                        top: 20,
                        right: 20,
                        child: Column(
                          children: [
                            // My Location button
                            Consumer<LocationProvider>(
                              builder: (context, locProvider, _) {
                                return FloatingActionButton.small(
                                  onPressed: () {
                                    if (locProvider.currentLocation != null) {
                                      _mapController.move(
                                        latlong.LatLng(
                                          locProvider.currentLocation!.latitude,
                                          locProvider
                                              .currentLocation!.longitude,
                                        ),
                                        13.0,
                                      );
                                    }
                                  },
                                  backgroundColor: Colors.white,
                                  child: const Icon(Icons.my_location,
                                      color: Colors.blue),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            // Refresh button
                            FloatingActionButton.small(
                              onPressed: _refreshMap,
                              backgroundColor: Colors.white,
                              child:
                                  const Icon(Icons.refresh, color: Colors.blue),
                            ),
                          ],
                        ),
                      ),

                      // Warning when tracking is not active
                      if (!locationProvider.isTracking)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.all(20),
                            margin: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.orange[200]!),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.location_off,
                                    color: Colors.orange[700], size: 48),
                                const SizedBox(height: 12),
                                Text(
                                  'Байршлын хянах идэвхгүй байна',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange[900],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Газрын зургийг ашиглахын тулд байршлын хянахыг эхлүүлнэ үү',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.orange[800],
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: () async {
                                    await locationProvider.startTracking();
                                    _refreshMap();
                                  },
                                  icon: const Icon(Icons.play_arrow),
                                  label: const Text('Хянах эхлүүлэх'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.orange[600],
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Loading indicator
                      if (locationProvider.isTracking &&
                          locationProvider.currentLocation == null &&
                          locationProvider.errorMessage == null)
                        const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text(
                                'Газрын зураг ачааллаж байна...',
                                style: TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ),

                      // Debug info overlay (for development)
                      Positioned(
                        bottom: 20,
                        left: 20,
                        right: 20,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                locationProvider.currentLocation != null
                                    ? 'Байршил: ${locationProvider.currentLocation!.latitude.toStringAsFixed(4)}, ${locationProvider.currentLocation!.longitude.toStringAsFixed(4)}'
                                    : 'Байршил: Мэдэгдээгүй',
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12),
                              ),
                              if (locationProvider.lastLocationUpdateTime !=
                                  null)
                                Text(
                                  'Шинэчлэгдсэн: ${locationProvider.lastLocationUpdateTimeString}',
                                  style: const TextStyle(
                                      color: Colors.green,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500),
                                ),
                              if (locationProvider.currentLocation != null &&
                                  locationProvider.currentLocation!.latitude ==
                                      47.9188)
                                const Text(
                                  'Түр зуурын байршил ашиглаж байна (GPS ажиллахгүй байна)',
                                  style: TextStyle(
                                      color: Colors.yellow, fontSize: 10),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Wake time display overlay
                      if (locationProvider.wakeTime != null)
                        Positioned(
                          top:
                              locationProvider.errorMessage != null ? 140 : 100,
                          left: 20,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.blue[200]!),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.wb_sunny,
                                    color: Colors.blue[700], size: 20),
                                const SizedBox(width: 8),
                                Text(
                                  'Ассан цаг: ${_formatDateTime(locationProvider.wakeTime!)}',
                                  style: TextStyle(
                                    color: Colors.blue[900],
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      // Error message overlay
                      if (locationProvider.errorMessage != null)
                        Positioned(
                          top: 80,
                          left: 20,
                          right: 20,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red[200]!),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning,
                                    color: Colors.red[600], size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    locationProvider.errorMessage!,
                                    style: TextStyle(
                                      color: Colors.red[700],
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),

            // Bottom info panel
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Consumer<LocationProvider>(
                    builder: (context, locationProvider, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Явсан цэг: ${locationProvider.locationHistory.length}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            'Дэлгүүр: ${widget.shops.length}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ],
                      );
                    },
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      final locationProvider =
                          Provider.of<LocationProvider>(context, listen: false);
                      locationProvider.clearHistory();
                      setState(() {});
                    },
                    icon: const Icon(Icons.clear_all, size: 16),
                    label: const Text('Түүх цэвэрлэх'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[100],
                      foregroundColor: Colors.red[700],
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final monthNames = [
      '1-р сар',
      '2-р сар',
      '3-р сар',
      '4-р сар',
      '5-р сар',
      '6-р сар',
      '7-р сар',
      '8-р сар',
      '9-р сар',
      '10-р сар',
      '11-р сар',
      '12-р сар'
    ];

    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');

    return '${dateTime.year}-${monthNames[dateTime.month - 1]} ${dateTime.day}, $hour:$minute';
  }

  Widget _buildLegendItem(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[700],
          ),
        ),
      ],
    );
  }

  void _showMapLegend() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Map тусламж'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Map дээрх тэмдэглэгээ:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('🔵 Цэнхэр цэг - Таны одоогийн байршил'),
              Text('🟢 Ногоон цэг - Дэлгүүрүүд'),
              Text('🟠 Улбар шар цэг - Агуулах'),
              Text('🟣 Цэнхэр шугам - Явсан маршрут'),
              SizedBox(height: 16),
              Text(
                'Функцууд:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('• Map дээр zoom хийж болно'),
              Text('• Тэмдэглэгээ дээр дараад дэлгэрэнгүй мэдээлэл харна'),
              Text('• "Түүх цэвэрлэх" товчоор явсан маршрутыг устгана'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Хаах'),
          ),
        ],
      ),
    );
  }
}
