import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:async';

import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/mobileUserLogin.dart';
import 'providers/location_provider.dart';
import 'providers/sales_provider.dart';
import 'providers/order_provider.dart';
import 'providers/product_provider.dart';
import 'providers/shop_provider.dart';
import 'providers/warehouse_provider.dart';
import 'services/warehouse_web_bridge.dart';
import 'theme/app_themes.dart';
import 'utils/app_router.dart';

void main() async {
  // Intl (month/day names) for mn_MN DateFormat usage — bindings шаарддаггүй.
  await initializeDateFormatting('mn_MN', null);

  runZonedGuarded(() {
    // `runApp`-тай ижил zone-д эхлүүлэх ёстой (Zone mismatch алдаа гарна).
    WidgetsFlutterBinding.ensureInitialized();

    // Log framework errors (incl. assertions) with stack traces.
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      if (kDebugMode) {
        debugPrint('=== FLUTTER ERROR ===');
        debugPrint(details.exceptionAsString());
        if (details.stack != null) {
          debugPrint(details.stack.toString());
        }
        debugPrint('=== END FLUTTER ERROR ===');
      }
    };

    // Catch async errors not routed through FlutterError.
    PlatformDispatcher.instance.onError = (error, stack) {
      if (kDebugMode) {
        debugPrint('=== PLATFORM DISPATCHER ERROR ===');
        debugPrint(error.toString());
        debugPrint(stack.toString());
        debugPrint('=== END PLATFORM DISPATCHER ERROR ===');
      }
      return true;
    };

    runApp(const MyApp());
  }, (error, stack) {
    if (kDebugMode) {
      debugPrint('=== ZONED ERROR ===');
      debugPrint(error.toString());
      debugPrint(stack.toString());
      debugPrint('=== END ZONED ERROR ===');
    }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Нэг удаа л үүсгэх (theme/dark mode солиход дахин үүсэхгүй) — нэвтрэх токен/provider эвдрэхээс сэргийлнэ.
  final WarehouseWebBridge _sharedBridge = WarehouseWebBridge();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(
            create: (_) => MobileUserLoginProvider(bridge: _sharedBridge)),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
        ChangeNotifierProvider(create: (_) => SalesProvider()),
        ChangeNotifierProvider(create: (_) => OrderProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => ShopProvider()),
        ChangeNotifierProvider(
            create: (_) => WarehouseProvider(bridge: _sharedBridge)),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, _) {
          return MaterialApp.router(
            title: 'Aguulga Business App',
            theme: AppThemes.light,
            darkTheme: AppThemes.dark,
            themeMode: themeProvider.themeMode,
            // Mobile optimizations
            builder: (context, child) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: MediaQuery.of(context).textScaler.clamp(
                        minScaleFactor: 0.8,
                        maxScaleFactor: 1.2,
                      ), // Allow text scaling for accessibility
                ),
                child: child!,
              );
            },
            routerConfig: AppRouter.router,
            debugShowCheckedModeBanner: false,
          );
        },
      ),
    );
  }
}
