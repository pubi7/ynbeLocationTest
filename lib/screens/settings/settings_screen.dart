import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlong;
import 'package:geolocator/geolocator.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../widgets/hamburger_menu.dart';
import '../../widgets/bottom_navigation.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificationsEnabled = true;
  bool _darkModeEnabled = false;
  bool _locationTrackingEnabled = true;
  bool _newSettingEnabled = false; // New boolean for the additional setting
  String _selectedLanguage = 'English';
  String _selectedCurrency = 'USD';
  String _selectedOption = 'Option 1'; // New String for the dropdown

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
      bottomNavigationBar: const BottomNavigationWidget(currentRoute: '/settings'),
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
                // Location Tracking Tile
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  leading: Icon(Icons.location_on_rounded, color: Colors.grey[600]),
                  title: const Text(
                    'Байршил хянах',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                  ),
                  subtitle: const Text(
                    'Машины хөдөлгөөнийг хянахыг зөвшөөрөх',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.map_rounded),
                        onPressed: _showLocationHistoryMap,
                        color: const Color(0xFF6366F1),
                        tooltip: 'Map харах',
                      ),
                      Switch(
                        value: _locationTrackingEnabled,
                        onChanged: (value) async {
                          final provider = Provider.of<LocationProvider>(
                            context, 
                            listen: false
                          );
                          if (value) {
                            await provider.startTracking();
                          } else {
                            provider.stopTracking();
                          }
                          setState(() => _locationTrackingEnabled = value);
                        },
                        activeColor: const Color(0xFF10B981),
                      ),
                    ],
                  ),
                  onTap: _showLocationHistoryMap, // Tap to open map directly
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

            // Language & Region Section
            _buildSectionCard(
              'Language & Region',
              Icons.language_rounded,
              const Color(0xFF8B5CF6),
              [
                _buildDropdownTile(
                  'Language',
                  'Select your preferred language',
                  Icons.translate_rounded,
                  _selectedLanguage,
                  ['English', 'Spanish', 'French', 'German', 'Chinese'],
                  (value) => setState(() => _selectedLanguage = value!),
                ),
                _buildDropdownTile(
                  'Currency',
                  'Select your preferred currency',
                  Icons.attach_money_rounded,
                  _selectedCurrency,
                  ['USD', 'EUR', 'GBP', 'JPY', 'CAD'],
                  (value) => setState(() => _selectedCurrency = value!),
                ),
                // New Dropdown Tile
                _buildDropdownTile(
                  'New Dropdown',
                  'Select an option',
                  Icons.list_rounded,
                  _selectedOption,
                  ['Option 1', 'Option 2', 'Option 3'],
                  (value) => setState(() => _selectedOption = value!),
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

            // Support Section
            _buildSectionCard(
              'Support',
              Icons.help_rounded,
              const Color(0xFFEF4444),
              [
                _buildActionTile(
                  'Help Center',
                  'Get help and support',
                  Icons.help_center_rounded,
                  () => _showHelpDialog(),
                ),
                _buildActionTile(
                  'Contact Us',
                  'Send us feedback',
                  Icons.contact_support_rounded,
                  () => _showContactDialog(),
                ),
                _buildActionTile(
                  'About',
                  'App version and information',
                  Icons.info_rounded,
                  () => _showAboutDialog(),
                ),
                // New Action Tile
                _buildActionTile(
                  'New Action',
                  'Tap to perform action',
                  Icons.touch_app_rounded,
                  () => _showCustomDialog(),
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

  Widget _buildSectionCard(String title, IconData icon, Color color, List<Widget> children) {
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
    return Consumer<AuthProvider>(
      builder: (context, authProvider, child) {
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF3B82F6).withOpacity(0.1),
            child: Icon(
              Icons.person_rounded,
              color: const Color(0xFF3B82F6),
            ),
          ),
          title: Text(
            authProvider.user?.name ?? 'User',
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          subtitle: Text(
            (authProvider.user?.role ?? 'user').toUpperCase(),
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit_rounded),
            onPressed: () => _showEditProfileDialog(),
          ),
        );
      },
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, IconData icon, bool value, Function(bool) onChanged) {
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

  Widget _buildDropdownTile(String title, String subtitle, IconData icon, String value, List<String> options, Function(String?) onChanged) {
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
      trailing: DropdownButton<String>(
        value: value,
        onChanged: onChanged,
        underline: const SizedBox(),
        items: options.map((String option) {
          return DropdownMenuItem<String>(
            value: option,
            child: Text(option),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActionTile(String title, String subtitle, IconData icon, VoidCallback onTap) {
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
        content: const Text('Profile editing functionality would be implemented here.'),
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
        content: const Text('Your data will be exported and sent to your email address.'),
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
        content: const Text('This will clear all cached data and free up storage space.'),
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

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Help Center'),
        content: const SingleChildScrollView(
          child: Text(
            'Need help? Contact our support team at support@aguulga.com or call +1-800-AGUULGA for assistance.',
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

  void _showContactDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contact Us'),
        content: const SingleChildScrollView(
          child: Text(
            'We\'d love to hear from you! Send us your feedback, suggestions, or report issues at feedback@aguulga.com',
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

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('About Aguulga Business App'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Version: 1.0.0'),
              SizedBox(height: 8),
              Text('Build: 2024.01.01'),
              SizedBox(height: 8),
              Text('Aguulga Business App helps you manage sales, orders, and track your team efficiently.'),
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
              await Provider.of<AuthProvider>(context, listen: false).logout();
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

  Future<void> _showLocationHistoryMap() async {
    // Get current location permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (!context.mounted) return;

    // Sample shop locations (in real app, this would come from your database)
    final List<Map<String, dynamic>> shops = [
      {
        'name': 'Дэлгүүр 1',
        'address': 'Сүхбаатар дүүрэг',
        'lat': 47.9200,
        'lng': 106.9200,
        'type': 'shop'
      },
      {
        'name': 'Дэлгүүр 2', 
        'address': 'Баянзүрх дүүрэг',
        'lat': 47.9150,
        'lng': 106.9150,
        'type': 'shop'
      },
      {
        'name': 'Агуулах',
        'address': 'Хан-Уул дүүрэг', 
        'lat': 47.9250,
        'lng': 106.9250,
        'type': 'warehouse'
      },
    ];

    // Get the location provider and start tracking if not already started
    final locationProvider = Provider.of<LocationProvider>(context, listen: false);
    
    // Always start tracking to get fresh location
    if (!locationProvider.isTracking) {
      await locationProvider.startTracking();
    } else {
      // If already tracking, try to update location
      try {
        await locationProvider.updateCurrentLocation();
      } catch (e) {
        print('Update location error: $e');
        // Continue anyway
      }
    }

    if (!context.mounted) return;

    showDialog(
      context: context,
      builder: (context) => Dialog(
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
                        onPressed: () => _showMapLegend(context),
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
                    _buildLegendItem(Icons.location_on, 'Одоо байгаа', Colors.blue),
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
                          options: MapOptions(
                            initialCenter: locationProvider.currentLocation != null 
                                ? latlong.LatLng(locationProvider.currentLocation!.latitude, locationProvider.currentLocation!.longitude)
                                : const latlong.LatLng(47.9188, 106.9177), // УБ хот төв
                            initialZoom: 13.0,
                            minZoom: 5.0,
                            maxZoom: 18.0,
                          ),
                          children: [
                            // Primary tile layer - OpenStreetMap
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.example.aguulgav3',
                              maxZoom: 18,
                              additionalOptions: const {
                                'attribution': '© OpenStreetMap contributors',
                              },
                            ),
                            
                            // Fallback tile layer - CartoDB
                            TileLayer(
                              urlTemplate: 'https://cartodb-basemaps-{s}.global.ssl.fastly.net/light_all/{z}/{x}/{y}.png',
                              subdomains: const ['a', 'b', 'c', 'd'],
                              userAgentPackageName: 'com.example.aguulgav3',
                              maxZoom: 18,
                              additionalOptions: const {
                                'attribution': '© CartoDB',
                              },
                            ),
                            
                            // Markers
                            MarkerLayer(
                              markers: [
                                // Current location marker
                                if (locationProvider.currentLocation != null)
                                  Marker(
                                    point: latlong.LatLng(locationProvider.currentLocation!.latitude, locationProvider.currentLocation!.longitude),
                                    width: 40,
                                    height: 40,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.blue,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 3),
                                      ),
                                      child: const Icon(
                                        Icons.location_on,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                                
                                // Shop markers
                                ...shops.map((shop) {
                                  return Marker(
                                    point: latlong.LatLng(shop['lat'], shop['lng']),
                                    width: 40,
                                    height: 40,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: shop['type'] == 'warehouse' ? Colors.orange : Colors.green,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 2),
                                      ),
                                      child: Icon(
                                        shop['type'] == 'warehouse' ? Icons.warehouse : Icons.store,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ],
                            ),
                            
                            // Route polyline
                            if (locationProvider.locationHistory.isNotEmpty)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: locationProvider.locationHistory,
                                    color: const Color(0xFF6366F1),
                                    strokeWidth: 4.0,
                                  ),
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
                              if (locationProvider.currentLocation != null)
                                FloatingActionButton.small(
                                  onPressed: () {
                                    // Center map on current location
                                    // This will be handled by FlutterMap's onMapEvent
                                  },
                                  backgroundColor: Colors.white,
                                  child: const Icon(Icons.my_location, color: Colors.blue),
                                ),
                              const SizedBox(height: 8),
                              // Refresh button
                              FloatingActionButton.small(
                                onPressed: () {
                                  locationProvider.startTracking();
                                },
                                backgroundColor: Colors.white,
                                child: const Icon(Icons.refresh, color: Colors.blue),
                              ),
                            ],
                          ),
                        ),
                        
                        // Legend overlay
                        Positioned(
                          top: 20,
                          left: 20,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (locationProvider.currentLocation != null)
                                  _buildMapMarker('Одоо байгаа', Colors.blue, Icons.location_on),
                                const SizedBox(height: 8),
                                _buildMapMarker('Дэлгүүр', Colors.green, Icons.store),
                                const SizedBox(height: 8),
                                _buildMapMarker('Агуулах', Colors.orange, Icons.warehouse),
                                const SizedBox(height: 8),
                                _buildMapMarker('Явсан зам', Colors.purple, Icons.timeline),
                              ],
                            ),
                          ),
                        ),
                        
                        // Loading indicator
                        if (locationProvider.currentLocation == null && locationProvider.errorMessage == null)
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
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                ),
                                if (locationProvider.currentLocation != null && locationProvider.currentLocation!.latitude == 47.9188)
                                  const Text(
                                    'Түр зуурын байршил ашиглаж байна (GPS ажиллахгүй байна)',
                                    style: TextStyle(color: Colors.yellow, fontSize: 10),
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
                                  Icon(Icons.warning, color: Colors.red[600], size: 20),
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
                        
                        // Location info
                        Positioned(
                          bottom: 20,
                          left: 20,
                          right: 20,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Одоогийн байршил:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[700],
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  locationProvider.currentLocation != null
                                      ? '${locationProvider.currentLocation!.latitude.toStringAsFixed(4)}, ${locationProvider.currentLocation!.longitude.toStringAsFixed(4)}'
                                      : (locationProvider.errorMessage ?? 'Байршил тодорхойлогдоогүй'),
                                  style: TextStyle(
                                    color: locationProvider.errorMessage != null ? Colors.red[600] : Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Явсан цэг: ${locationProvider.locationHistory.length}',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Дэлгүүр: 3',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Агуулах: 1',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
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
                              'Дэлгүүр: ${shops.length}',
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ],
                        );
                      },
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _clearLocationHistory(),
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
      ),
    );
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

  Widget _buildMapMarker(String label, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _showMapLegend(BuildContext context) {
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

  void _clearLocationHistory() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Түүх цэвэрлэх'),
        content: const Text('Та явсан маршрутын түүхийг бүрэн устгахдаа итгэлтэй байна уу?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Цуцлах'),
          ),
          ElevatedButton(
            onPressed: () {
              Provider.of<LocationProvider>(context, listen: false).clearHistory();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Явсан маршрутын түүх цэвэрлэгдлээ')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Устгах'),
          ),
        ],
      ),
    );
  }

  void _showCustomDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom Action'),
        content: const Text('You tapped on the new action tile!'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
