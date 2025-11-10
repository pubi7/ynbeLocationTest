import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class BottomNavigationWidget extends StatelessWidget {
  final String currentRoute;
  
  const BottomNavigationWidget({
    super.key,
    required this.currentRoute,
  });

  @override
  Widget build(BuildContext context) {
    return _buildSalesBottomNav(context);
  }

  Widget _buildSalesBottomNav(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildBottomNavItem(
                context,
                'Sales',
                Icons.sell_rounded,
                const Color(0xFF10B981),
                '/sales-history',
                currentRoute == '/sales-history',
              ),
              _buildBottomNavItem(
                context,
                'Orders',
                Icons.shopping_cart_rounded,
                const Color(0xFF3B82F6),
                '/sales-orders',
                currentRoute == '/sales-orders',
              ),
              _buildBottomNavItem(
                context,
                'Settings',
                Icons.settings_rounded,
                const Color(0xFF6B7280),
                '/settings',
                currentRoute == '/settings',
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildBottomNavItem(
    BuildContext context,
    String label,
    IconData icon,
    Color color,
    String route,
    bool isActive,
  ) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => context.go(route),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: isActive ? color.withOpacity(0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isActive ? color.withOpacity(0.2) : color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: isActive ? color : color.withOpacity(0.7),
                    size: 20,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                    color: isActive ? color : color.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
