import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../models/order_model.dart';
import '../screens/auth/login_screen.dart';
import '../screens/sales/sales_dashboard.dart';
import '../screens/sales/sales_entry_screen.dart';
import '../screens/sales/order_screen.dart';
import '../screens/sales/sales_history_screen.dart';
import '../screens/sales/orders_screen.dart';
import '../screens/sales/order_details_screen.dart';
import '../screens/sales/performance_screen.dart';
import '../screens/settings/settings_screen.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final authProvider = context.read<AuthProvider>();
      final isLoggedIn = authProvider.isLoggedIn;
      final role = authProvider.userRole;
      final goingToLogin = state.uri.path == '/login';

      // If not logged in, force login for everything except /login.
      if (!isLoggedIn) {
        return goingToLogin ? null : '/login';
      }

      // If logged in, don't allow staying on /login.
      if (goingToLogin) {
        return role == 'order' ? '/order-screen' : '/sales-dashboard';
      }

      bool isAllowedForRole(String role, String path) {
        if (role == 'order') {
          return path == '/sales-dashboard' ||
              path == '/order-screen' ||
              path == '/sales-orders' ||
              path.startsWith('/order-details') ||
              path == '/settings';
        }
        // default to sales
        return path == '/sales-dashboard' ||
            path == '/performance' ||
            path == '/sales-entry' ||
            path == '/sales-history' ||
            path == '/settings';
      }

      final path = state.uri.path;
      if (!isAllowedForRole(role, path)) {
        return role == 'order' ? '/order-screen' : '/sales-dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/sales-dashboard',
        builder: (context, state) => const SalesDashboard(),
      ),
      GoRoute(
        path: '/sales-entry',
        builder: (context, state) => const SalesEntryScreen(),
      ),
      GoRoute(
        path: '/order-screen',
        builder: (context, state) => const OrderScreen(),
      ),
      GoRoute(
        path: '/sales-history',
        builder: (context, state) => const SalesHistoryScreen(),
      ),
      GoRoute(
        path: '/sales-orders',
        builder: (context, state) => const OrdersScreen(),
      ),
      GoRoute(
        path: '/performance',
        builder: (context, state) => const PerformanceScreen(),
      ),
      GoRoute(
        path: '/order-details/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return OrderDetailsScreen(orderId: id, order: state.extra is Order ? state.extra as Order : null);
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}

