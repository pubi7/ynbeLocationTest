import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../models/order_model.dart';
import '../screens/auth/login_screen.dart';
import '../screens/sales/sales_dashboard.dart';
import '../screens/sales/sales_entry_screen.dart';
import '../screens/sales/order_screen.dart';
import '../screens/sales/orders_screen.dart';
import '../screens/sales/order_details_screen.dart';
import '../screens/sales/returnable_ebarimt_orders_screen.dart';
import '../screens/sales/performance_screen.dart';
import '../screens/sales/sales_map_screen.dart';
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

      // Хуучин /sales-history холбоосыг хадгалсан хэрэглэгчдэд
      if (state.uri.path == '/sales-history') {
        return role == 'order' ? '/order-screen' : '/sales-dashboard';
      }

      bool isAllowedForRole(String role, String path) {
        if (role == 'order') {
          return path == '/sales-dashboard' ||
              path == '/order-screen' ||
              path == '/sales-orders' ||
              path == '/sales-orders/returnable-ebarimt' ||
              path.startsWith('/order-details') ||
              path == '/settings';
        }
        // default to sales
        return path == '/sales-dashboard' ||
            path == '/performance' ||
            path == '/sales-entry' ||
            path == '/sales-map' ||
            path == '/settings' ||
            path == '/sales-orders' ||
            path == '/sales-orders/returnable-ebarimt' ||
            path.startsWith('/order-details');
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
        path: '/sales-orders',
        builder: (context, state) => const OrdersScreen(),
      ),
      GoRoute(
        path: '/sales-orders/returnable-ebarimt',
        builder: (context, state) {
          final extra = state.extra;
          final list =
              extra is List<Order> ? List<Order>.from(extra) : <Order>[];
          final note = state.uri.queryParameters['note'];
          return ReturnableEbarimtOrdersScreen(
            orders: list,
            subtitle: note,
          );
        },
      ),
      GoRoute(
        path: '/performance',
        builder: (context, state) => const PerformanceScreen(),
      ),
      GoRoute(
        path: '/sales-map',
        builder: (context, state) => const SalesMapScreen(),
      ),
      GoRoute(
        path: '/order-details/:id',
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          return OrderDetailsScreen(
              orderId: id,
              order: state.extra is Order ? state.extra as Order : null);
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}
