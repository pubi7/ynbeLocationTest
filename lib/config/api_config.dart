/// API тохиргооны файл
///
/// Backend Scraper API тохируулах:
/// 1. Node.js backend сервер ажиллуулах (server.js файл)
/// 2. Backend серверийн URL-ийг доор оруулах
///
/// Backend сервер нь opendatalab.mn-ийг scrape хийж JSON буцаадаг
///
/// ⚠️ Flutter Web ашиглаж байгаа бол:
/// - localhost ашиглахгүй байх нь дээр
/// - Computer-ийн IP хаяг ашиглах (жишээ: http://192.168.1.100:3000)
/// - IP хаяг олох: Windows дээр `ipconfig`, Mac/Linux дээр `ifconfig`
library api_config;

import 'platform_info.dart';

class ApiConfig {
  /// Override using:
  /// - Flutter: `--dart-define=WAREHOUSE_API_BASE_URL=http://<host>:3001/api`
  /// - Flutter: `--dart-define=BACKEND_SERVER_URL=http://<host>:3001`
  static const String _warehouseApiBaseUrlOverride =
      String.fromEnvironment('WAREHOUSE_API_BASE_URL', defaultValue: '');
  static const String _backendServerUrlOverride =
      String.fromEnvironment('BACKEND_SERVER_URL', defaultValue: '');

  static String _trimTrailingSlash(String s) {
    if (s.endsWith('/')) return s.substring(0, s.length - 1);
    return s;
  }

  static String _ensureTrailingSlash(String s) {
    if (s.isEmpty) return s;
    return s.endsWith('/') ? s : '$s/';
  }

  // Backend Scraper API URL (Node.js сервер)
  // ТА ЭНД BACKEND СЕРВЕРИЙН URL ОРУУЛНА УУ
  //
  // Flutter Web ашиглаж байгаа бол:
  // - localhost биш computer IP ашиглах (жишээ: 'http://192.168.1.100:3000')
  // - IP хаяг олох: Windows дээр `ipconfig` командыг ажиллуулах
  //
  // Flutter Mobile (Android Emulator) ашиглаж байгаа бол:
  // - 'http://10.0.2.2:3000' ашиглах (host PC руу redirect хийнэ)
  //
  // Flutter Mobile (iOS Simulator) ашиглаж байгаа бол:
  // - 'http://localhost:3000' ашиглаж болно
  //
  // Production дээр:
  // - HTTPS ашиглах (жишээ: 'https://your-server.com')
  // Warehouse Management System Backend API
  // Warehouse Service Main Backend API URL
  // Mobile app ашиглаж байгаа бол:
  // - Android Emulator: 'http://10.0.2.2:3000' (host PC руу redirect хийнэ)
  // - iOS Simulator: 'http://localhost:3000'
  // - Physical Device: Computer IP хаяг ашиглах (жишээ: 'http://192.168.114.200:3000')
  // - Flutter Web: Computer IP хаяг ашиглах
  // NOTE: This default points to your LOCAL docker backend published on host port 3000.
  // Change via --dart-define, or adjust the defaults below.
  static String get backendServerUrl {
    if (_backendServerUrlOverride.isNotEmpty)
      return _trimTrailingSlash(_backendServerUrlOverride);

    // Warehouse backend (warehouse-service-main) runs on port 3000
    // Flutter Web: localhost works
    // Android Emulator: 10.0.2.2 (host loopback)
    // Physical Phone: Use PC LAN IP (192.168.1.6)
    // iOS Simulator: localhost works
    if (PlatformInfo.isWeb) {
      return 'http://localhost:3000';
    }
    // Mobile devices - use LAN IP
    return 'http://192.168.1.6:3000';
  }

  // Warehouse API Base URL
  static String get warehouseApiBaseUrl {
    // Ensure trailing slash so Dio correctly joins paths like `auth/login`
    // (otherwise it can become `/apiauth/login`).
    if (_warehouseApiBaseUrlOverride.isNotEmpty) {
      return _ensureTrailingSlash(_warehouseApiBaseUrlOverride);
    }
    return _ensureTrailingSlash('${backendServerUrl}/api');
  }

  // Backend сервер идэвхтэй эсэхийг шалгах
  static bool get isBackendServerEnabled {
    return backendServerUrl.isNotEmpty;
  }

  // Google Custom Search API (fallback - одоогоор ашиглахгүй)
  static const String googleApiKey = 'YOUR_GOOGLE_API_KEY';
  static const String googleSearchEngineId = 'YOUR_SEARCH_ENGINE_ID';
}
