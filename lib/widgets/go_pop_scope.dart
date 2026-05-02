import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

/// `context.go()` нь түүхийн стек үүсгэхгүй тул Android/iOS системийн «буцах»
/// дарахад [fallbackRoute] руу шилжүүлнэ.
class GoPopScope extends StatelessWidget {
  const GoPopScope({
    super.key,
    required this.child,
    required this.fallbackRoute,
  });

  final Widget child;

  /// Жишээ: `/sales-dashboard`, `/sales-orders`
  final String fallbackRoute;

  static String homeRouteFor(BuildContext context) {
    final role = context.read<AuthProvider>().userRole;
    return role == 'order' ? '/order-screen' : '/sales-dashboard';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!context.mounted) return;
        context.go(fallbackRoute);
      },
      child: child,
    );
  }
}
