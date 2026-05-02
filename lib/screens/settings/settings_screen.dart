import 'package:flutter/material.dart';
import 'dart:io';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/mobileUserLogin.dart';
import '../../providers/location_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/shop_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../config/api_config.dart';
import '../../widgets/go_pop_scope.dart';
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
  bool _newSettingEnabled = false; // New boolean for the additional setting
  // Language & Region section removed

  static const _profileImagePathKey = 'profile_image_path';
  String? _profileImagePath;

  // Warehouse web connection
  static const _warehouseApiBaseUrlKey = 'warehouse_api_base_url';
  final _warehouseApiBaseUrlController =
      TextEditingController(text: ApiConfig.defaultBackendServerUrl);
  final _warehouseEmailController =
      TextEditingController(text: 'agent@oasis.mn');
  final _warehousePasswordController = TextEditingController(text: 'agent123');

  @override
  void initState() {
    super.initState();
    _loadWarehouseApiBaseUrl();
    _loadProfileImagePath();
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

  Future<void> _loadProfileImagePath() async {
    final prefs = await SharedPreferences.getInstance();
    final p = prefs.getString(_profileImagePathKey);
    if (!mounted) return;
    setState(() {
      _profileImagePath = (p != null && p.trim().isNotEmpty) ? p.trim() : null;
    });
  }

  Future<void> _pickAndSaveProfileImage() async {
    try {
      final picker = ImagePicker();
      final x = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (x == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_profileImagePathKey, x.path);
      if (!mounted) return;
      setState(() {
        _profileImagePath = x.path;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Зураг сонгоход алдаа: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _removeProfileImage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_profileImagePathKey);
    if (!mounted) return;
    setState(() {
      _profileImagePath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GoPopScope(
      fallbackRoute: GoPopScope.homeRouteFor(context),
      child: Scaffold(
        backgroundColor: scheme.surface,
        appBar: AppBar(
          title: const Text('Settings'),
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
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
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primary,
                    scheme.secondary,
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
                      color: scheme.onPrimary.withValues(alpha: 0.9),
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
                                  decoration: InputDecoration(
                                    labelText: 'Server URL',
                                    helperText:
                                        'Локал warehouse-service: порт 3000. Эмулятор: ${ApiConfig.localWarehouseUrlAndroidEmulator}. Default: ${ApiConfig.defaultBackendServerUrl}.',
                                    helperMaxLines: 3,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    ActionChip(
                                      label: const Text('Локал эмулятор'),
                                      onPressed: warehouseProvider.isLoading
                                          ? null
                                          : () async {
                                              const u = ApiConfig
                                                  .localWarehouseUrlAndroidEmulator;
                                              setState(() =>
                                                  _warehouseApiBaseUrlController
                                                      .text = u);
                                              await _saveWarehouseApiBaseUrl(u);
                                              await warehouseProvider
                                                  .updateApiBaseUrl(u);
                                            },
                                    ),
                                    ActionChip(
                                      label: const Text('Локал 127.0.0.1'),
                                      onPressed: warehouseProvider.isLoading
                                          ? null
                                          : () async {
                                              const u = ApiConfig
                                                  .localWarehouseUrlLoopback;
                                              setState(() =>
                                                  _warehouseApiBaseUrlController
                                                      .text = u);
                                              await _saveWarehouseApiBaseUrl(u);
                                              await warehouseProvider
                                                  .updateApiBaseUrl(u);
                                            },
                                    ),
                                    ActionChip(
                                      label: const Text('Production'),
                                      onPressed: warehouseProvider.isLoading
                                          ? null
                                          : () async {
                                              final u = ApiConfig
                                                  .productionBackendServerUrl;
                                              setState(() =>
                                                  _warehouseApiBaseUrlController
                                                      .text = u);
                                              await _saveWarehouseApiBaseUrl(u);
                                              await warehouseProvider
                                                  .updateApiBaseUrl(u);
                                            },
                                    ),
                                  ],
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
                Consumer<ThemeProvider>(
                  builder: (context, themeProvider, _) {
                    return _buildSwitchTile(
                      'Dark Mode',
                      'Use dark theme',
                      Icons.dark_mode_rounded,
                      themeProvider.themeMode == ThemeMode.dark,
                      (value) => themeProvider.setDarkMode(value),
                    );
                  },
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
                        activeThumbColor: Theme.of(context).colorScheme.primary,
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
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
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
                            ? btPrinter.connectedPrinterName ??
                                'Принтер холбоотой'
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
      ),
    );
  }

  Widget _buildSectionCard(
      String title, IconData icon, Color color, List<Widget> children) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
                alpha: scheme.brightness == Brightness.dark ? 0.35 : 0.05),
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
                    color: color.withValues(
                        alpha:
                            scheme.brightness == Brightness.dark ? 0.18 : 0.1),
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
                    color: scheme.brightness == Brightness.dark
                        ? scheme.onSurface
                        : color,
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
        final scheme = Theme.of(context).colorScheme;
        // Get display name - prefer displayName from backend, fallback to name
        final displayName = authProvider.user?.name ?? 'User';
        final roleDisplay = (authProvider.user?.role ?? 'user').toUpperCase();

        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF3B82F6).withValues(
                alpha: scheme.brightness == Brightness.dark ? 0.22 : 0.1),
            backgroundImage: (_profileImagePath != null &&
                    File(_profileImagePath!).existsSync())
                ? FileImage(File(_profileImagePath!))
                : null,
            child: (_profileImagePath == null ||
                    !File(_profileImagePath!).existsSync())
                ? const Icon(
                    Icons.person_rounded,
                    color: Color(0xFF3B82F6),
                  )
                : null,
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
                  color: scheme.onSurfaceVariant,
                  fontSize: 14,
                ),
              ),
              if (warehouseProvider.connected &&
                  authProvider.user?.email != null)
                Text(
                  authProvider.user?.email ?? '',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Зураг сонгох',
                icon: const Icon(Icons.photo_camera_rounded),
                onPressed: _pickAndSaveProfileImage,
              ),
              if (_profileImagePath != null)
                IconButton(
                  tooltip: 'Зураг устгах',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: _removeProfileImage,
                ),
              IconButton(
                icon: const Icon(Icons.edit_rounded),
                onPressed: () => _showEditProfileDialog(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, IconData icon,
      bool value, Function(bool) onChanged) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: scheme.onSurfaceVariant),
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
          color: scheme.onSurfaceVariant,
          fontSize: 14,
        ),
      ),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: scheme.primary,
      ),
    );
  }

  // Dropdown section removed

  Widget _buildActionTile(
      String title, String subtitle, IconData icon, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: Icon(icon, color: scheme.onSurfaceVariant),
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
          color: scheme.onSurfaceVariant,
          fontSize: 14,
        ),
      ),
      trailing: Icon(Icons.chevron_right_rounded,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.85)),
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
