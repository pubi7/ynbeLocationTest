import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../screens/auth/login_screen.dart';
import '../screens/sales/sales_dashboard.dart';
import '../screens/sales/sales_entry_screen.dart';
import '../screens/sales/order_screen.dart';
import '../screens/sales/sales_history_screen.dart';
import '../screens/sales/orders_screen.dart';
import '../screens/settings/settings_screen.dart';

class AppRouter {
  static final GoRouter router = GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      // Allow specific routes without redirect
      if (state.uri.path == '/sales-history' ||
          state.uri.path == '/sales-orders' ||
          state.uri.path == '/sales-entry' ||
          state.uri.path == '/order-screen' ||
          state.uri.path == '/settings') {
        return null;
      }
      
      final authProvider = context.read<AuthProvider>();
      final isLoggedIn = authProvider.isLoggedIn;
      
      if (!isLoggedIn) {
        return '/login';
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
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
    ],
  );
}

