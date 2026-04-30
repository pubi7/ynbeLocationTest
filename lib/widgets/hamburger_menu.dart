import 'package:flutter/material.dart';
import 'dart:io';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import '../utils/role_utils.dart';

class HamburgerMenu extends StatelessWidget {
  const HamburgerMenu({super.key});

  static const _profileImagePathKey = 'profile_image_path';

  @override
  Widget build(BuildContext context) {
    final authProvider = context.read<AuthProvider>();
    final isLoggedIn = authProvider.isLoggedIn;
    final role = authProvider.userRole;
    // `User.name` is non-null when `user` exists; keep it null when logged out
    // so we don't render the literal "null".
    final userName = authProvider.user?.name.trim();
    final currentPath = GoRouterState.of(context).uri.toString();
    final scheme = Theme.of(context).colorScheme;

    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.primary,
              scheme.secondary,
            ],
          ),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      FutureBuilder<String?>(
                        future: SharedPreferences.getInstance().then(
                          (p) => p.getString(_profileImagePathKey),
                        ),
                        builder: (context, snap) {
                          final path = snap.data?.trim();
                          final has = path != null &&
                              path.isNotEmpty &&
                              File(path).existsSync();
                          return CircleAvatar(
                            radius: 22,
                            backgroundColor:
                                scheme.onPrimary.withValues(alpha: 0.16),
                            backgroundImage: has ? FileImage(File(path)) : null,
                            child: has
                                ? null
                                : const Icon(Icons.menu_rounded,
                                    color: Colors.white, size: 22),
                          );
                        },
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName != null && userName.isNotEmpty
                                  ? userName
                                  : (isLoggedIn ? 'Хэрэглэгч' : 'Menu'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              isLoggedIn
                                  ? (role == 'order'
                                      ? 'Захиалга'
                                      : 'Борлуулалт')
                                  : 'Нэвтрээгүй байна',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.90),
                                fontSize: 14,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Menu Items
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  // color is set below using theme to support dark mode
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(20),
                    topRight: Radius.circular(20),
                  ),
                ),
                foregroundDecoration: null,
                child: ColoredBox(
                  color: scheme.surface,
                  child: SafeArea(
                    top: false,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                      children: [
                        _buildSectionTitle('Үндсэн'),
                        _buildMenuItem(
                          context,
                          title: 'Dashboard',
                          icon: Icons.dashboard_rounded,
                          color: const Color(0xFF6366F1),
                          active: _isActive(currentPath, '/sales-dashboard'),
                          onTap: () => _navigateToDashboard(context),
                        ),
                        if (role != 'order')
                          _buildMenuItem(
                            context,
                            title: (!isManagerRole(role) && isAgentRole(role))
                                ? 'Захиалга үүсгэх'
                                : 'Шууд хэвлэх',
                            icon: (!isManagerRole(role) && isAgentRole(role))
                                ? Icons.shopping_cart_checkout_rounded
                                : Icons.point_of_sale_rounded,
                            color: const Color(0xFF3B82F6),
                            active: _isActive(currentPath, '/sales-entry'),
                            onTap: () => context.go('/sales-entry'),
                          ),
                        if (role != 'order')
                          _buildMenuItem(
                            context,
                            title: 'Захиалгын жагсаалт',
                            icon: Icons.list_alt_rounded,
                            color: const Color(0xFF06B6D4),
                            active: _isActive(currentPath, '/sales-orders'),
                            onTap: () => context.go('/sales-orders'),
                          ),
                        if (role != 'order')
                          _buildMenuItem(
                            context,
                            title: 'Гүйцэтгэл',
                            icon: Icons.insights_rounded,
                            color: const Color(0xFF10B981),
                            active: _isActive(currentPath, '/performance'),
                            onTap: () => context.go('/performance'),
                          ),
                        if (role != 'order')
                          _buildMenuItem(
                            context,
                            title: 'Газрын зураг',
                            icon: Icons.map_rounded,
                            color: const Color(0xFF0D9488),
                            active: _isActive(currentPath, '/sales-map'),
                            onTap: () => context.go('/sales-map'),
                          ),
                        if (role == 'order') ...[
                          const SizedBox(height: 8),
                          _buildSectionTitle('Захиалга'),
                          _buildMenuItem(
                            context,
                            title: 'Захиалга авах',
                            icon: Icons.shopping_cart_rounded,
                            color: const Color(0xFF3B82F6),
                            active: _isActive(currentPath, '/order-screen'),
                            onTap: () => context.go('/order-screen'),
                          ),
                          _buildMenuItem(
                            context,
                            title: 'Захиалгын жагсаалт',
                            icon: Icons.list_alt_rounded,
                            color: const Color(0xFF06B6D4),
                            active: _isActive(currentPath, '/sales-orders'),
                            onTap: () => context.go('/sales-orders'),
                          ),
                        ],
                        const SizedBox(height: 8),
                        _buildSectionTitle('Тохиргоо'),
                        _buildMenuItem(
                          context,
                          title: 'Settings',
                          icon: Icons.settings_rounded,
                          color: const Color(0xFF64748B),
                          active: _isActive(currentPath, '/settings'),
                          onTap: () => context.go('/settings'),
                        ),
                        const SizedBox(height: 10),
                        const Divider(height: 18),
                        if (!isLoggedIn)
                          _buildMenuItem(
                            context,
                            title: 'Нэвтрэх',
                            icon: Icons.login_rounded,
                            color: const Color(0xFF6366F1),
                            active: _isActive(currentPath, '/login'),
                            onTap: () => context.go('/login'),
                          ),
                        if (isLoggedIn)
                          _buildMenuItem(
                            context,
                            title: 'Гарах',
                            icon: Icons.logout_rounded,
                            color: const Color(0xFFEF4444),
                            active: false,
                            onTap: () => _handleLogout(context),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _isActive(String currentPath, String targetPath) {
    if (currentPath == targetPath) return true;
    return currentPath.startsWith('$targetPath/');
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF64748B),
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildMenuItem(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required bool active,
    required VoidCallback onTap,
  }) {
    final bg =
        active ? color.withValues(alpha: 0.14) : color.withValues(alpha: 0.08);
    final border =
        active ? color.withValues(alpha: 0.55) : color.withValues(alpha: 0.18);
    final titleColor =
        active ? const Color(0xFF0F172A) : const Color(0xFF1F2937);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        leading: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: active ? FontWeight.w800 : FontWeight.w600,
            color: titleColor,
            fontSize: 15,
          ),
        ),
        trailing: active
            ? Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              )
            : null,
        onTap: () {
          Navigator.pop(context); // Close drawer
          onTap();
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }

  void _navigateToDashboard(BuildContext context) {
    context.go('/sales-dashboard');
  }

  void _handleLogout(BuildContext context) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    await authProvider.logout();
    if (context.mounted) {
      context.go('/login');
    }
  }
}
