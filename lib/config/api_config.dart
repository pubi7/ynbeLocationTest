/// API тохиргооны файл
///
/// Backend Scraper API тохируулах:
/// 1. Node.js backend сервер ажиллуулах (server.js файл)
/// 2. Backend серверийн URL-ийг доор оруулах
///
/// Backend (proxy) нь шаардлагатай бол opendatalab.mn руу серверээс хандаж JSON буцаадаг;
/// Flutter апп шууд opendatalab руу дуудахгүй.
///
/// **Production** суурь: [productionBackendServerUrl].
///
/// HTTPS + **зөвхөн IP** (`https://1.2.3.4`) — сертификат ихэвчлэн **домэйнд** зориулагдсан
/// тул `CERTIFICATE_VERIFY_FAILED` / IP mismatch гарна. Шийдэл: `BACKEND_SERVER_URL`-д
/// сертификаттай домэйн оруулах. Дотоод тестэд түр: `--dart-define=WAREHOUSE_TLS_INSECURE=true`.
///
/// **Тест / staging** орчин:
/// - `flutter run --dart-define=BACKEND_ENV=test`
/// - Зайлшгүй биш боловч тест серверийн host: `--dart-define=TEST_BACKEND_SERVER_URL=http://127.0.0.1:3000`
/// - Бүх compile-time URL-ийг нэг дор дарж: `--dart-define=BACKEND_SERVER_URL=https://...` (энэ нь дээрхээс илүүдэнлэн)
///
/// VS Code: «ynbeLocationTest (test backend)» launch тохиргоо.
library api_config;

class ApiConfig {
  /// `production` | `test` | `staging` — жишээ нь тест backend руу шилжих.
  static const String backendEnv = String.fromEnvironment(
    'BACKEND_ENV',
    defaultValue: 'production',
  );

  /// Тест эсвэл staging горим эсэх (`BACKEND_ENV` нь `test` / `staging`).
  static bool get isTestOrStagingBackend {
    final e = backendEnv.toLowerCase();
    return e == 'test' || e == 'staging' || e == 'dev';
  }

  /// Production warehouse API суурь.
  ///
  /// **IP дээр `https://...`** — сертификат ихэвчлэн домэйнд зориулагдсан тул
  /// `CERTIFICATE_VERIFY_FAILED: IP address mismatch` гарна. Ийм тохиолдолд:
  /// - түр: `http://IP` (доорх анхдагч), эсвэл `--dart-define=WAREHOUSE_TLS_INSECURE=true` + `https://IP`;
  /// - зөв: DNS+TLS-тай домэйн (`BACKEND_SERVER_URL` / Тохиргоо).
  ///
  /// **Домэйн** — public DNS-д A/AAAA байх ёстой; үгүй бол `Failed host lookup`.
  ///
  /// `:80` дээр **nginx 404 (HTML)** гарвал `/api`-г Node backend руу proxy хийгээгүй;
  /// түрд `http://IP:3000` (порт нээлттэй бол) эсвэл nginx тохируулна.
  static const String productionBackendServerUrl = 'http://43.231.115.209:3000';

  /// TLS сертификат шалгалтыг алгасах (**зөвхөн дотоод тест**).
  ///
  /// `flutter run --dart-define=WAREHOUSE_TLS_INSECURE=true`
  ///
  /// Production-д ашиглахгүй; MITM-д өртөмтгий.
  static const bool warehouseTlsInsecure = bool.fromEnvironment(
    'WAREHOUSE_TLS_INSECURE',
    defaultValue: false,
  );

  /// `false` (анхдагч): апп `SharedPreferences`-ийн `warehouse_api_base_url`-ийг **үл тоож**,
  /// зөвхөн [backendServerUrl] / [warehouseApiBaseUrl] (production эсвэл dart-define)-ийг ашиглана —
  /// мобайлаас серверийн хаяг **өөрчлөгдөхгүй**.
  ///
  /// Локал / staging-д prefs-ээр солих: `--dart-define=ALLOW_WAREHOUSE_URL_OVERRIDE=true`
  static const bool allowWarehouseUrlOverride = bool.fromEnvironment(
    'ALLOW_WAREHOUSE_URL_OVERRIDE',
    defaultValue: false,
  );

  /// Тест backend суурь (host only, `/api` хасна).
  ///
  /// Анхдагч: локал `warehouse-service` (`npm run dev`, порт 3000).
  static const String _testBackendServerUrlDefine = String.fromEnvironment(
    'TEST_BACKEND_SERVER_URL',
    // Default тест горимд ч production серверийг ашиглая (login дээр server URL нуусан тул).
    defaultValue: productionBackendServerUrl,
  );

  /// Нэвтрэх дэлгэц / тохиргооны анхны placeholder — орчноос хамаарна.
  static String get defaultBackendServerUrl {
    if (isTestOrStagingBackend) {
      return _trimTrailingSlash(_testBackendServerUrlDefine);
    }
    return _trimTrailingSlash(productionBackendServerUrl);
  }

  /// Локал warehouse-service (`npm run dev`, PORT=3000).
  ///
  /// - Android **эмулятор**: PC дээрх `localhost:3000` руу `10.0.2.2` дамжина.
  /// - **Бодит утас**: PC-ийн LAN IP (`http://192.168.x.x:3000`) оруулна.
  /// - **Windows/macOS desktop** апп: `127.0.0.1`.
  static const String localWarehouseUrlAndroidEmulator = 'http://10.0.2.2:3000';
  static const String localWarehouseUrlLoopback = 'http://127.0.0.1:3000';

  /// Override using:
  /// - Flutter: `--dart-define=WAREHOUSE_API_BASE_URL=https://<host>/api/`
  /// - Flutter: `--dart-define=BACKEND_SERVER_URL=https://<host>`
  /// - HTTPS + IP mismatch түр шийдэх (зөвхөн тест): `--dart-define=WAREHOUSE_TLS_INSECURE=true`
  static const String _warehouseApiBaseUrlOverride =
      String.fromEnvironment('WAREHOUSE_API_BASE_URL', defaultValue: '');
  static const String _backendServerUrlOverride =
      String.fromEnvironment('BACKEND_SERVER_URL', defaultValue: '');

  /// И-баримт: `branchNo`, `posNo`, district, VAT зэргийг **backend** (PosAPI руу дуудахдаа)
  /// бэлдэнэ; mobile зөвхөн `POST /api/ebarimt/register/:orderId` дамжуулна.

  /// Барааны үнэ **НӨАТ-гүй** (net) гэж үзэх (API талбар эсвэл энэ тэмдэглэлээр).
  ///
  /// Дэлгэц/сагсанд net үнэ харагдана; баримтын НӨАТ нэмэх нь `SalesItem.receiptLineGross` гэх мэт.
  ///
  /// Идэвхжүүлэх: `--dart-define=WAREHOUSE_PRICES_EXCLUDE_VAT=true`
  /// Идэвхгүй: `--dart-define=WAREHOUSE_PRICES_EXCLUDE_VAT=false`
  /// Эсвэл бүтээгдэхүүн дээр `vatIncluded: true` / `priceIncludesVat: true`.
  static const bool warehousePricesExcludeVat = bool.fromEnvironment(
    'WAREHOUSE_PRICES_EXCLUDE_VAT',
    defaultValue: true,
  );

  static String _trimTrailingSlash(String s) {
    if (s.endsWith('/')) return s.substring(0, s.length - 1);
    return s;
  }

  static String _ensureTrailingSlash(String s) {
    if (s.isEmpty) return s;
    return s.endsWith('/') ? s : '$s/';
  }

  static String get backendServerUrl {
    if (_backendServerUrlOverride.isNotEmpty) {
      return _trimTrailingSlash(_backendServerUrlOverride);
    }
    return defaultBackendServerUrl;
  }

  // Warehouse API Base URL
  static String get warehouseApiBaseUrl {
    // Ensure trailing slash so Dio correctly joins paths like `auth/login`
    // (otherwise it can become `/apiauth/login`).
    if (_warehouseApiBaseUrlOverride.isNotEmpty) {
      return _ensureTrailingSlash(_warehouseApiBaseUrlOverride);
    }
    final base = backendServerUrl;
    if (base.isEmpty) return '';
    return _ensureTrailingSlash('$base/api');
  }

  // Backend сервер идэвхтэй эсэхийг шалгах
  static bool get isBackendServerEnabled {
    return backendServerUrl.isNotEmpty;
  }

  // Google Custom Search API (fallback - одоогоор ашиглахгүй)
  static const String googleApiKey = 'YOUR_GOOGLE_API_KEY';
  static const String googleSearchEngineId = 'YOUR_SEARCH_ENGINE_ID';
}
