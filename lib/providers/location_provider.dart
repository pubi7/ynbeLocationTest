import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import '../config/api_config.dart';
import '../utils/warehouse_agent_shop_identity_one_file.dart';

class LocationProvider extends ChangeNotifier {
  // ---- Tuning knobs (reduce noisy updates) ----
  static const Duration _backendSyncInterval = Duration(minutes: 10);
  static const double _minDistanceToSendToBackendMeters =
      100; // send only if moved enough
  static const Duration _minTimeBetweenBackendSends = Duration(minutes: 5);

  LatLng? _lastBackendSentLocation;
  DateTime? _lastBackendSentAt;
  LatLng? _currentLocation;
  List<LatLng> _locationHistory = [];
  final Map<int, LatLng> _orderLocationsCache = {};
  StreamSubscription<Position>? _positionSub;
  Timer? _locationUpdateTimer; // 2 секунд тутамд байршлыг шинэчлэх timer
  Timer? _backendSyncTimer; // Backend руу байршил илгээх timer
  bool _isTracking = false;
  String? _errorMessage;
  bool _isLocationServiceEnabled = false;
  bool _useIpOnlyMode = false; // Зөвхөн IP хаягаар байршлыг тодорхойлох горим
  DateTime? _wakeTime; // Ассан цаг
  DateTime? _sleepTime; // Унтаасан цаг
  DateTime? _lastLocationUpdateTime; // GPS байршлын сүүлийн шинэчлэлтийн цаг
  String? _currentIpAddress; // Одоогийн IP хаяг
  static const double _minDistanceToSave =
      20.0; // 20 метрийн хүрээ доторх хөдөлгөөнийг хадгалахгүй
  int? _currentAgentId; // Одоогийн борлуулагчийн ID

  // Storage keys
  static const String _locationHistoryKey = 'location_history';
  static const String _currentLocationKey = 'current_location';
  static const String _wakeTimeKey = 'wake_time';
  static const String _sleepTimeKey = 'sleep_time';
  static const String _autoStartLocationKey = 'auto_start_location_tracking';
  static const String _orderLocationsKey = 'order_locations_v1';
  bool _autoStartEnabled = true;

  LocationProvider() {
    _loadSavedLocations();
    _loadSavedTimes();
    _loadAutoStartPref();
    _loadAgentId();
    _loadOrderLocationsCache();
  }

  Future<void> _loadOrderLocationsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_orderLocationsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      _orderLocationsCache.clear();
      for (final e in decoded.entries) {
        final v = e.value;
        if (v is! Map) continue;
        final id = int.tryParse(e.key.toString());
        final lat = (v['latitude'] as num?)?.toDouble();
        final lng = (v['longitude'] as num?)?.toDouble();
        if (id == null || lat == null || lng == null) continue;
        if (lat == 0.0 && lng == 0.0) continue;
        _orderLocationsCache[id] = LatLng(lat, lng);
      }
      notifyListeners();
    } catch (_) {}
  }

  /// Load agent ID from SharedPreferences
  Future<void> _loadAgentId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentAgentId = prefs.getInt(WarehouseAgentShopIdentity.prefsAgentIdKey);
      if (_currentAgentId != null) {
        print('✅ Agent ID ачаалагдлаа: $_currentAgentId');
      }
    } catch (e) {
      print('Алдаа: Agent ID ачаалах: $e');
    }
  }

  /// Set agent ID
  Future<void> setAgentId(int agentId) async {
    _currentAgentId = agentId;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(WarehouseAgentShopIdentity.prefsAgentIdKey, agentId);
      print('✅ Agent ID хадгалагдлаа: $agentId');
    } catch (e) {
      print('Алдаа: Agent ID хадгалах: $e');
    }
    notifyListeners();
  }

  /// Send location to backend (Weve сайт `GET /api/agents/locations/all` эндээс уншина).
  /// [recordedAt] — түүхийн цэг болгон хадгалахыг backend дэмжвэл илгээнэ.
  Future<bool> _sendLocationToBackend(
    LatLng location, {
    DateTime? recordedAt,
  }) async {
    if (_currentAgentId == null) {
      print('⚠️  Agent ID байхгүй, backend руу илгээх боломжгүй');
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      // Use warehouse_token - same as WarehouseWebBridge (app saves token with this key)
      final token = prefs.getString('warehouse_token');

      if (token == null) {
        print('⚠️  Auth token байхгүй');
        return false;
      }

      String baseUrl = ApiConfig.backendServerUrl;
      final savedApi = prefs.getString('warehouse_api_base_url');
      if (savedApi != null && savedApi.trim().isNotEmpty) {
        var s = savedApi.trim();
        if (s.endsWith('/')) s = s.substring(0, s.length - 1);
        if (s.toLowerCase().endsWith('/api')) {
          baseUrl = s.substring(0, s.length - 4);
        } else {
          baseUrl = s;
        }
      }
      if (baseUrl.isEmpty) {
        print('Server URL тохируулаагүй, location илгээхгүй');
        return false;
      }
      final url = Uri.parse('$baseUrl/api/agents/$_currentAgentId/location');

      final body = <String, dynamic>{
        'latitude': location.latitude,
        'longitude': location.longitude,
        'ipAddress': _currentIpAddress,
        'accuracy': 10.0, // Default accuracy
      };
      if (recordedAt != null) {
        body['recordedAt'] = recordedAt.toUtc().toIso8601String();
      }

      final response = await http
          .post(
            url,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        print(
            '✅ Байршил backend руу илгээгдлээ: ${location.latitude}, ${location.longitude}');
        return true;
      } else {
        print('❌ Backend алдаа: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ Backend руу байршил илгээх алдаа: $e');
      return false;
    }
  }

  /// Газрын зураг дээрх байршлын түүхийг Weve/backend руу цэг бүрээр илгээнэ.
  /// Хэт олон бол сүүлийн [maxPoints] цэгийг л илгээнэ (давхар ойролцоо цэгүүдийг шүүж).
  Future<Map<String, int>> syncLocationHistoryToWeveBackend({
    int maxPoints = 250,
    Duration delayBetween = const Duration(milliseconds: 150),
  }) async {
    var ok = 0;
    var fail = 0;
    if (_currentAgentId == null) {
      return {'ok': 0, 'fail': 0};
    }

    final raw = <LatLng>[..._locationHistory];
    if (_currentLocation != null) {
      raw.add(_currentLocation!);
    }

    // Давхар дараалсан ижил координатыг нэг болгоно
    final deduped = <LatLng>[];
    for (final p in raw) {
      if (deduped.isEmpty) {
        deduped.add(p);
        continue;
      }
      final last = deduped.last;
      if (last.latitude == p.latitude && last.longitude == p.longitude) {
        continue;
      }
      deduped.add(p);
    }

    final start = deduped.length > maxPoints ? deduped.length - maxPoints : 0;
    final slice = deduped.sublist(start);

    for (final p in slice) {
      final success = await _sendLocationToBackend(p);
      if (success) {
        ok++;
      } else {
        fail++;
      }
      await Future<void>.delayed(delayBetween);
    }

    if (kDebugMode) {
      debugPrint(
          '[LocationProvider] Weve sync: $ok амжилттай, $fail алдаа (${slice.length} цэг)');
    }
    return {'ok': ok, 'fail': fail};
  }

  /// Start periodic backend sync (every 2 minutes)
  void _startBackendSync() {
    _backendSyncTimer?.cancel();
    _backendSyncTimer = Timer.periodic(
      _backendSyncInterval,
      (Timer timer) async {
        if (_isTracking &&
            _currentLocation != null &&
            _shouldSendToBackend(_currentLocation!)) {
          final ok = await _sendLocationToBackend(_currentLocation!);
          if (ok) {
            _lastBackendSentLocation = _currentLocation;
            _lastBackendSentAt = DateTime.now();
          }
        }
      },
    );
    print(
        '🔄 Backend sync эхлүүлэгдлээ (${_backendSyncInterval.inMinutes} минут тутамд)');
  }

  bool _shouldSendToBackend(LatLng loc) {
    final now = DateTime.now();
    final lastAt = _lastBackendSentAt;
    if (lastAt != null &&
        now.difference(lastAt) < _minTimeBetweenBackendSends) {
      return false;
    }
    final lastLoc = _lastBackendSentLocation;
    if (lastLoc == null) return true;
    final d = Geolocator.distanceBetween(
      lastLoc.latitude,
      lastLoc.longitude,
      loc.latitude,
      loc.longitude,
    );
    return d >= _minDistanceToSendToBackendMeters;
  }

  LatLng? get currentLocation => _currentLocation;

  /// Backend/warehouse profile-оос ирсэн борлуулагчийн ID (захиалгыг шүүхэд ашиглана).
  int? get currentAgentId => _currentAgentId;
  List<LatLng> get locationHistory => _locationHistory;
  bool get isTracking => _isTracking;
  String? get errorMessage => _errorMessage;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;
  bool get useIpOnlyMode => _useIpOnlyMode; // Зөвхөн IP горим
  DateTime? get wakeTime => _wakeTime; // Ассан цаг
  DateTime? get sleepTime => _sleepTime; // Унтаасан цаг
  DateTime? get lastLocationUpdateTime =>
      _lastLocationUpdateTime; // GPS байршлын сүүлийн шинэчлэлтийн цаг
  String? get currentIpAddress => _currentIpAddress; // Одоогийн IP хаяг
  bool get autoStartEnabled => _autoStartEnabled;

  /// OrderId-аар хадгалсан байршлыг синк байдлаар авах (cache).
  LatLng? getOrderLocationSync(int orderId) => _orderLocationsCache[orderId];

  /// Захиалга (backend orderId)-ын байршил хадгалах (апп дахин ачаалсан ч үлдэнэ).
  /// Энэ нь backend заавал хадгалахгүй байсан ч газрын зураг/тайлан дээр ашиглах “local cache” юм.
  Future<void> saveOrderLocation({
    required int orderId,
    required LatLng location,
    String? shopName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_orderLocationsKey);
      final Map<String, dynamic> map = (raw == null || raw.isEmpty)
          ? <String, dynamic>{}
          : (jsonDecode(raw) as Map).cast<String, dynamic>();

      map[orderId.toString()] = {
        'orderId': orderId,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'shopName': shopName,
        'ipAddress': _currentIpAddress,
        'capturedAt': DateTime.now().toIso8601String(),
      };

      await prefs.setString(_orderLocationsKey, jsonEncode(map));
      _orderLocationsCache[orderId] = location;
      notifyListeners();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('saveOrderLocation failed: $e');
      }
    }
  }

  /// Хадгалсан захиалгын байршил авах (байхгүй бол null).
  Future<LatLng?> getSavedOrderLocation(int orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_orderLocationsKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final v = decoded[orderId.toString()];
      if (v is! Map) return null;
      final lat = (v['latitude'] as num?)?.toDouble();
      final lng = (v['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      if (lat == 0.0 && lng == 0.0) return null;
      return LatLng(lat, lng);
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadAutoStartPref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _autoStartEnabled = prefs.getBool(_autoStartLocationKey) ?? true;

      // Auto-start location tracking on app entry (user requested: "ороход шууд асаа").
      // Skip on web to avoid unexpected permission prompts in browser.
      if (_autoStartEnabled && !kIsWeb) {
        Future.microtask(() => startTracking());
      }
    } catch (e) {
      // If prefs fails, default behavior: auto-start on mobile.
      _autoStartEnabled = true;
      if (!kIsWeb) {
        Future.microtask(() => startTracking());
      }
    }
    notifyListeners();
  }

  Future<void> setAutoStartEnabled(bool enabled) async {
    _autoStartEnabled = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_autoStartLocationKey, enabled);
    } catch (_) {}
    notifyListeners();

    if (enabled && !kIsWeb) {
      await startTracking();
    }
  }

  /// Check if location should be added to history (20 meter minimum distance)
  bool _shouldAddToHistory(LatLng newLocation) {
    if (_locationHistory.isEmpty) {
      return true; // Эхний байршлыг хадгалах
    }

    double distance = Geolocator.distanceBetween(
      _locationHistory.last.latitude,
      _locationHistory.last.longitude,
      newLocation.latitude,
      newLocation.longitude,
    );

    // Хэрэв 20 метрээс ойр байвал хадгалахгүй
    if (distance < _minDistanceToSave) {
      print(
          'Байршил 20 метрээс ойр тул хадгалахгүй: ${distance.toStringAsFixed(2)}м');
      return false;
    }

    return true;
  }

  /// Get formatted string for last location update time
  String get lastLocationUpdateTimeString {
    if (_lastLocationUpdateTime == null) return 'Мэдэгдээгүй';

    final now = DateTime.now();
    final difference = now.difference(_lastLocationUpdateTime!);

    if (difference.inSeconds < 60) {
      return '${difference.inSeconds} секунд өмнө';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} минут өмнө';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} цаг өмнө';
    } else {
      return '${difference.inDays} өдөр өмнө';
    }
  }

  /// Load saved locations from SharedPreferences
  Future<void> _loadSavedLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load current location
      final currentLocationJson = prefs.getString(_currentLocationKey);
      if (currentLocationJson != null) {
        final Map<String, dynamic> locationMap =
            jsonDecode(currentLocationJson);
        _currentLocation = LatLng(
          locationMap['latitude'] as double,
          locationMap['longitude'] as double,
        );
      }

      // Load location history
      final historyJson = prefs.getString(_locationHistoryKey);
      if (historyJson != null) {
        final List<dynamic> historyList = jsonDecode(historyJson);
        _locationHistory = historyList.map((item) {
          return LatLng(
            item['latitude'] as double,
            item['longitude'] as double,
          );
        }).toList();
      }

      notifyListeners();
    } catch (e) {
      print('Алдаа: Хадгалагдсан байршлыг ачаалах: $e');
    }
  }

  /// Load saved wake and sleep times from SharedPreferences
  Future<void> _loadSavedTimes() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Load wake time
      final wakeTimeString = prefs.getString(_wakeTimeKey);
      if (wakeTimeString != null) {
        _wakeTime = DateTime.parse(wakeTimeString);
      }

      // Load sleep time
      final sleepTimeString = prefs.getString(_sleepTimeKey);
      if (sleepTimeString != null) {
        _sleepTime = DateTime.parse(sleepTimeString);
      }

      notifyListeners();
    } catch (e) {
      print('Алдаа: Хадгалагдсан цагийг ачаалах: $e');
    }
  }

  /// Save wake and sleep times to SharedPreferences
  Future<void> _saveTimes() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save wake time
      if (_wakeTime != null) {
        await prefs.setString(_wakeTimeKey, _wakeTime!.toIso8601String());
      } else {
        await prefs.remove(_wakeTimeKey);
      }

      // Save sleep time
      if (_sleepTime != null) {
        await prefs.setString(_sleepTimeKey, _sleepTime!.toIso8601String());
      } else {
        await prefs.remove(_sleepTimeKey);
      }
    } catch (e) {
      print('Алдаа: Цагийг хадгалах: $e');
    }
  }

  /// Set wake time (Ассан цаг)
  Future<void> setWakeTime(DateTime wakeTime) async {
    _wakeTime = wakeTime;
    await _saveTimes();
    notifyListeners();
  }

  /// Set sleep time (Унтаасан цаг)
  Future<void> setSleepTime(DateTime sleepTime) async {
    _sleepTime = sleepTime;
    await _saveTimes();
    notifyListeners();
  }

  /// Set current time as wake time (Одоогийн цагийг ассан цаг болгох)
  Future<void> setCurrentTimeAsWakeTime() async {
    await setWakeTime(DateTime.now());
  }

  /// Set current time as sleep time (Одоогийн цагийг унтаасан цаг болгох)
  Future<void> setCurrentTimeAsSleepTime() async {
    await setSleepTime(DateTime.now());
  }

  /// Clear wake time (Ассан цагийг устгах)
  Future<void> clearWakeTime() async {
    _wakeTime = null;
    await _saveTimes();
    notifyListeners();
  }

  /// Clear sleep time (Унтаасан цагийг устгах)
  Future<void> clearSleepTime() async {
    _sleepTime = null;
    await _saveTimes();
    notifyListeners();
  }

  /// Save locations to SharedPreferences
  Future<void> _saveLocations() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Save current location
      if (_currentLocation != null) {
        final locationMap = {
          'latitude': _currentLocation!.latitude,
          'longitude': _currentLocation!.longitude,
        };
        await prefs.setString(_currentLocationKey, jsonEncode(locationMap));
      }

      // Save location history
      final historyList = _locationHistory.map((location) {
        return {
          'latitude': location.latitude,
          'longitude': location.longitude,
        };
      }).toList();
      await prefs.setString(_locationHistoryKey, jsonEncode(historyList));
    } catch (e) {
      print('Алдаа: Байршлыг хадгалах: $e');
    }
  }

  /// Зөвхөн IP горимд ажиллах
  void setIpOnlyMode(bool enabled) {
    _useIpOnlyMode = enabled;
    if (enabled) {
      // GPS tracking-ийг зогсоох
      stopTracking();
      // IP-аар байршлыг тодорхойлох
      _startIpOnlyTracking();
    }
    notifyListeners();
  }

  /// Зөвхөн IP хаягаар байршлыг тодорхойлох
  Future<void> _startIpOnlyTracking() async {
    try {
      _errorMessage = null;
      _isTracking = true;
      _isLocationServiceEnabled = false;

      // IP хаяг авах
      final ip = await _getIpAddress();
      if (ip != null) {
        _currentIpAddress = ip;

        // IP хаягаар байршлыг тодорхойлох
        final ipLocation = await _getLocationFromIp(ip);
        if (ipLocation != null) {
          _currentLocation = ipLocation;
          if (_shouldAddToHistory(_currentLocation!)) {
            _locationHistory.add(_currentLocation!);
          }
          _lastLocationUpdateTime = DateTime.now();
          await _saveLocations();
          print(
              '✅ IP хаягаар байршил тодорхойллоо: ${ipLocation.latitude}, ${ipLocation.longitude}');
          _errorMessage = null;
          notifyListeners();
        } else {
          _errorMessage = 'IP хаягаар байршил тодорхойлох боломжгүй.';
          notifyListeners();
        }
      } else {
        _errorMessage = 'IP хаяг авах боломжгүй.';
        notifyListeners();
      }

      // IP хаягийг тогтмол шинэчлэх (30 секунд тутамд)
      _locationUpdateTimer?.cancel();
      _locationUpdateTimer =
          Timer.periodic(const Duration(seconds: 30), (timer) async {
        final newIp = await _getIpAddress();
        if (newIp != null && newIp != _currentIpAddress) {
          _currentIpAddress = newIp;
          final ipLocation = await _getLocationFromIp(newIp);
          if (ipLocation != null) {
            _currentLocation = ipLocation;
            if (_shouldAddToHistory(_currentLocation!)) {
              _locationHistory.add(_currentLocation!);
            }
            _lastLocationUpdateTime = DateTime.now();
            await _saveLocations();
            print(
                '✅ IP хаягаар байршил шинэчлэгдлээ: ${ipLocation.latitude}, ${ipLocation.longitude}');
            notifyListeners();
          }
        }
      });
    } catch (e) {
      print('❌ IP горим алдаа: $e');
      _errorMessage = 'IP горимд алдаа гарлаа: $e';
      notifyListeners();
    }
  }

  Future<void> startTracking() async {
    // Зөвхөн IP горимд ажиллах
    if (_useIpOnlyMode) {
      await _startIpOnlyTracking();
      return;
    }

    try {
      _errorMessage = null;

      // IP хаяг авах болон IP-аар байршлыг тодорхойлох
      _getIpAddress().then((ip) async {
        if (ip != null) {
          _currentIpAddress = ip;

          // IP хаягаар байршлыг тодорхойлох
          final ipLocation = await _getLocationFromIp(ip);
          if (ipLocation != null && _currentLocation == null) {
            // GPS байршил байхгүй бол IP-аар олсон байршлыг ашиглах
            _currentLocation = ipLocation;
            if (_shouldAddToHistory(_currentLocation!)) {
              _locationHistory.add(_currentLocation!);
            }
            _lastLocationUpdateTime = DateTime.now();
            await _saveLocations();
            print(
                '✅ IP хаягаар байршил тодорхойллоо: ${ipLocation.latitude}, ${ipLocation.longitude}');
            notifyListeners();
          }

          notifyListeners();
        }
      });

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Try to use last known position even when service is disabled (offline mode)
        try {
          Position? lastKnownPos = await Geolocator.getLastKnownPosition();
          if (lastKnownPos != null &&
              lastKnownPos.latitude != 0.0 &&
              lastKnownPos.longitude != 0.0) {
            _currentLocation =
                LatLng(lastKnownPos.latitude, lastKnownPos.longitude);
            if (_shouldAddToHistory(_currentLocation!)) {
              _locationHistory.add(_currentLocation!);
            }
            _lastLocationUpdateTime =
                DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
            await _saveLocations();
            _isTracking = true;
            _isLocationServiceEnabled = false;
            _errorMessage =
                null; // Сүүлийн мэдэгдсэн байршил ашиглаж байгаа үед алдаа харуулахгүй
            notifyListeners();
            print(
                'Офлайн горим: Сүүлийн мэдэгдсэн байршил ашиглалаа: ${lastKnownPos.latitude}, ${lastKnownPos.longitude}');
            return;
          }
        } catch (e) {
          print('Офлайн горимд сүүлийн байршил авах алдаа: $e');
        }

        // Try to use saved location
        if (_currentLocation != null) {
          _isTracking = true;
          _isLocationServiceEnabled = false;
          _errorMessage =
              null; // Хадгалагдсан байршил ашиглаж байгаа үед алдаа харуулахгүй
          notifyListeners();
          print(
              'Офлайн горим: Хадгалагдсан байршил ашиглалаа: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
          return;
        }

        // GPS байхгүй бол IP-аар олсон байршлыг ашиглах
        if (_currentLocation == null) {
          // IP хаяг авах хүлээх (2 секунд)
          await Future.delayed(const Duration(seconds: 2));
        }

        if (_currentLocation != null) {
          _isTracking = true;
          _isLocationServiceEnabled = false;
          _errorMessage =
              null; // IP-аар олсон байршил ашиглаж байгаа үед алдаа харуулахгүй
          notifyListeners();
          print(
              'Офлайн горим: IP хаягаар байршил тодорхойллоо: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
          return;
        }

        // Сүүлчийн оролдлого: түр зуурын байршил (УБ төв) ашиглах - газрын зураг харагдахаар болгох
        if (_currentLocation == null) {
          useFakeLocation();
          _errorMessage =
              'GPS ажиллахгүй байна. Түр зуурын байршил (УБ төв) харуулж байна.';
          notifyListeners();
          return;
        }

        _errorMessage =
            'Байршлын үйлчилгээ идэвхгүй байна. Тохиргооноос идэвхжүүлнэ үү.';
        _isLocationServiceEnabled = false;
        notifyListeners();

        // Try to open location settings
        bool serviceEnabledNow = await Geolocator.openLocationSettings();
        if (serviceEnabledNow) {
          // If user enabled it, try again
          return await startTracking();
        }
        return;
      }

      _isLocationServiceEnabled = true;

      // Check and request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();

        // Wait a bit for permission dialog
        await Future.delayed(const Duration(milliseconds: 500));

        // Check again after user responds
        permission = await Geolocator.checkPermission();
      }

      if (permission == LocationPermission.denied) {
        _errorMessage =
            'Байршлын зөвшөөрөл олгоогүй. Тохиргооноос зөвшөөрнө үү.';
        notifyListeners();
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        _errorMessage =
            'Байршлын зөвшөөрөл бүрэн хориглогдсон. Тохиргооноос дахин идэвхжүүлнэ үү.';
        notifyListeners();
        // Try to open app settings
        await Geolocator.openAppSettings();
        return;
      }

      _isTracking = true;
      notifyListeners();

      // Start backend sync
      _startBackendSync();

      // Try to get current position first with better accuracy
      try {
        Position currentPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 15),
          forceAndroidLocationManager: false,
        ).timeout(
          const Duration(seconds: 20),
        );

        if (currentPos.latitude != 0.0 && currentPos.longitude != 0.0) {
          _currentLocation = LatLng(currentPos.latitude, currentPos.longitude);
          if (_shouldAddToHistory(_currentLocation!)) {
            _locationHistory.add(_currentLocation!);
          }
          _lastLocationUpdateTime =
              DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
          await _saveLocations();
          _errorMessage = null;
          notifyListeners();
          // Эхний байршлыг шууд backend руу илгээх (Weve сайт дээр харагдана)
          await _sendLocationToBackend(_currentLocation!);
        } else {
          throw Exception('Invalid GPS coordinates');
        }
      } catch (e) {
        print('GPS алдаа: $e');
        // Only use fake location if we're sure GPS isn't working
        // Try once more with lower accuracy
        try {
          Position currentPos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 10),
          ).timeout(
            const Duration(seconds: 15),
          );

          if (currentPos.latitude != 0.0 && currentPos.longitude != 0.0) {
            _currentLocation =
                LatLng(currentPos.latitude, currentPos.longitude);
            if (_shouldAddToHistory(_currentLocation!)) {
              _locationHistory.add(_currentLocation!);
            }
            _lastLocationUpdateTime =
                DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
            await _saveLocations();
            _errorMessage = null;
            notifyListeners();
          } else {
            throw Exception('Invalid GPS coordinates');
          }
        } catch (e2) {
          print('GPS хоёр дахь оролдлого бас алдаатай: $e2');

          // Try to get last known position (works offline)
          try {
            Position? lastKnownPos = await Geolocator.getLastKnownPosition();
            if (lastKnownPos != null &&
                lastKnownPos.latitude != 0.0 &&
                lastKnownPos.longitude != 0.0) {
              _currentLocation =
                  LatLng(lastKnownPos.latitude, lastKnownPos.longitude);
              if (_shouldAddToHistory(_currentLocation!)) {
                _locationHistory.add(_currentLocation!);
              }
              _lastLocationUpdateTime =
                  DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
              await _saveLocations();
              _errorMessage =
                  null; // Сүүлийн мэдэгдсэн байршил ашиглаж байгаа үед алдаа харуулахгүй
              notifyListeners();
              print(
                  'Сүүлийн мэдэгдсэн байршил ашиглалаа: ${lastKnownPos.latitude}, ${lastKnownPos.longitude}');
            } else {
              throw Exception('Last known position not available');
            }
          } catch (e3) {
            print('Сүүлийн мэдэгдсэн байршил байхгүй: $e3');

            // Try to use saved location from SharedPreferences
            if (_currentLocation != null) {
              _errorMessage =
                  null; // Хадгалагдсан байршил ашиглаж байгаа үед алдаа харуулахгүй
              notifyListeners();
              print(
                  'Хадгалагдсан байршил ашиглалаа: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
            } else {
              _errorMessage =
                  'GPS оффлайн байна. Түр зуурын байршил ашиглаж байна.';
              useFakeLocation();
            }
          }
        }
      }

      // Start position stream with better settings
      LocationSettings settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Жижиг зайгаар шинэчлэх (илүү нарийвчлалтай)
        timeLimit: Duration(seconds: 15),
      );

      await _positionSub?.cancel();
      _positionSub =
          Geolocator.getPositionStream(locationSettings: settings).listen(
        (Position pos) {
          if (pos.latitude != 0.0 && pos.longitude != 0.0) {
            final newLocation = LatLng(pos.latitude, pos.longitude);

            _currentLocation = newLocation;

            // 20 метрийн хүрээ доторх хөдөлгөөнийг хадгалахгүй
            if (_shouldAddToHistory(_currentLocation!)) {
              _locationHistory.add(_currentLocation!);
            }

            _lastLocationUpdateTime =
                DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
            _errorMessage = null; // Clear error when we get location
            _saveLocations();

            // Backend руу минут тутам push хийхгүй — хөдөлгөөн/интервалын нөхцөл хангахад л илгээнэ.
            if (_shouldSendToBackend(newLocation)) {
              Future.microtask(() async {
                final ok = await _sendLocationToBackend(newLocation);
                if (ok) {
                  _lastBackendSentLocation = newLocation;
                  _lastBackendSentAt = DateTime.now();
                }
              });
            }
            notifyListeners();
          }
        },
        onError: (error) {
          print('GPS stream алдаа: $error');
          _errorMessage = 'Байршил авах алдаа: ${error.toString()}';
          notifyListeners();
        },
        cancelOnError: false, // Continue listening even on error
      );

      // NOTE: 1 минутын давтамжтай force-save таймер шаардлагагүй.
      // Stream update бүр дээр _saveLocations() дуудагдаж байгаа (distanceFilter=5m).
    } catch (e) {
      print('Start tracking алдаа: $e');
      _errorMessage = 'Байршил хянах эхлүүлэх алдаа: ${e.toString()}';
      notifyListeners();
    }
  }

  void stopTracking() {
    // IP горим унтраах
    if (_useIpOnlyMode) {
      _locationUpdateTimer?.cancel();
      _useIpOnlyMode = false;
    }
    _isTracking = false;
    _positionSub?.cancel();
    _positionSub = null;
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = null;
    _backendSyncTimer?.cancel();
    _backendSyncTimer = null;
    notifyListeners();
  }

  /// Захиалга бүртгэх мөчид борлуулагчийн байршлыг нэг удаа шинэчилж газрын зураг/түүхэнд тааруулна.
  /// IP-горимд IP geolocation-оор шинэчилнэ. GPS бол getCurrentPosition (+ шаардлагатай бол сүүлийн байршил).
  Future<LatLng?> refreshLocationForOrderRecording() async {
    if (_useIpOnlyMode) {
      return _captureLocationIpModeForOrder();
    }

    try {
      if (kIsWeb) {
        LocationPermission wPerm = await Geolocator.checkPermission();
        if (wPerm == LocationPermission.denied) {
          wPerm = await Geolocator.requestPermission();
          await Future.delayed(const Duration(milliseconds: 300));
          wPerm = await Geolocator.checkPermission();
        }
        if (wPerm != LocationPermission.denied &&
            wPerm != LocationPermission.deniedForever) {
          final webLoc = await _trySingleGpsReading(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 12),
            overallTimeout: const Duration(seconds: 14),
          );
          if (webLoc != null) {
            await _applyCapturedLocationForOrder(webLoc);
            return webLoc;
          }
        }
        return _currentLocation;
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        try {
          final last = await Geolocator.getLastKnownPosition();
          if (last != null && last.latitude != 0.0 && last.longitude != 0.0) {
            final loc = LatLng(last.latitude, last.longitude);
            await _applyCapturedLocationForOrder(loc);
            return loc;
          }
        } catch (_) {}
        return _currentLocation;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        await Future.delayed(const Duration(milliseconds: 400));
        permission = await Geolocator.checkPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _currentLocation;
      }

      LatLng? loc = await _trySingleGpsReading(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 12),
        overallTimeout: const Duration(seconds: 16),
      );
      loc ??= await _trySingleGpsReading(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
        overallTimeout: const Duration(seconds: 11),
      );

      if (loc != null) {
        await _applyCapturedLocationForOrder(loc);
        return loc;
      }

      try {
        final lastKnown = await Geolocator.getLastKnownPosition();
        if (lastKnown != null &&
            lastKnown.latitude != 0.0 &&
            lastKnown.longitude != 0.0) {
          loc = LatLng(lastKnown.latitude, lastKnown.longitude);
          await _applyCapturedLocationForOrder(loc);
          return loc;
        }
      } catch (_) {}
    } catch (e) {
      if (kDebugMode) {
        debugPrint('refreshLocationForOrderRecording: $e');
      }
    }
    return _currentLocation;
  }

  Future<LatLng?> _captureLocationIpModeForOrder() async {
    try {
      final ip = await _getIpAddress();
      if (ip != null) {
        _currentIpAddress = ip;
        final ipLoc = await _getLocationFromIp(ip);
        if (ipLoc != null) {
          await _applyCapturedLocationForOrder(ipLoc);
          return ipLoc;
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('_captureLocationIpModeForOrder: $e');
      }
    }
    return _currentLocation;
  }

  Future<LatLng?> _trySingleGpsReading({
    required LocationAccuracy desiredAccuracy,
    required Duration timeLimit,
    required Duration overallTimeout,
  }) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: desiredAccuracy,
        timeLimit: timeLimit,
        forceAndroidLocationManager: false,
      ).timeout(overallTimeout);
      if (pos.latitude != 0.0 && pos.longitude != 0.0) {
        return LatLng(pos.latitude, pos.longitude);
      }
    } catch (_) {}
    return null;
  }

  Future<void> _applyCapturedLocationForOrder(LatLng loc) async {
    _currentLocation = loc;
    if (_shouldAddToHistory(loc)) {
      _locationHistory.add(loc);
    }
    _lastLocationUpdateTime = DateTime.now();
    await _saveLocations();
    notifyListeners();
    if (_currentAgentId != null) {
      Future.microtask(() => _sendLocationToBackend(loc));
    }
  }

  void clearHistory() {
    _locationHistory.clear();
    _saveLocations();
    notifyListeners();
  }

  void addShopLocation(String name, String address, double lat, double lng) {
    // This method can be used to add shop locations programmatically
    // For now, shops are hardcoded in the settings screen
  }

  /// Use fake location for testing/debugging in simulators
  void useFakeLocation() {
    // Set a sample location in Ulaanbaatar city center
    _currentLocation = const LatLng(47.9188, 106.9177); // УБ хот төв
    if (_shouldAddToHistory(_currentLocation!)) {
      if (!_locationHistory.isEmpty) {
        _locationHistory.add(_currentLocation!);
      } else {
        _locationHistory = [_currentLocation!];
      }
    }
    _lastLocationUpdateTime = DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
    _errorMessage = null;
    _isTracking = true;
    _isLocationServiceEnabled = true;
    _saveLocations();
    notifyListeners();
  }

  /// IP хаяг авах
  Future<String?> _getIpAddress() async {
    try {
      // Олон API endpoint-үүдийг турших
      final endpoints = [
        'https://api.ipify.org?format=json',
        'https://api.ipify.org',
        'https://ipapi.co/json/',
        'https://ipinfo.io/json',
      ];

      for (var endpoint in endpoints) {
        try {
          final response = await http
              .get(
                Uri.parse(endpoint),
              )
              .timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final body = response.body.trim();
            // JSON эсэхийг шалгах
            if (body.startsWith('{')) {
              final json = jsonDecode(body);
              final ip = json['ip'] ?? json['query'] ?? json['origin'];
              if (ip != null) {
                print('✅ IP хаяг олдлоо: $ip');
                return ip.toString();
              }
            } else {
              // Зөвхөн IP хаяг буцаадаг API (ipify.org)
              if (RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$')
                  .hasMatch(body)) {
                print('✅ IP хаяг олдлоо: $body');
                return body;
              }
            }
          }
        } catch (e) {
          print('⚠️ IP хаяг авах алдаа ($endpoint): $e');
          continue;
        }
      }

      print('❌ IP хаяг олдсонгүй');
      return null;
    } catch (e) {
      print('❌ IP хаяг авах ерөнхий алдаа: $e');
      return null;
    }
  }

  /// IP хаягаар байршлыг тодорхойлох
  Future<LatLng?> _getLocationFromIp(String ipAddress) async {
    try {
      // IP geolocation API endpoint-үүд
      final endpoints = [
        'https://ipapi.co/$ipAddress/json/',
        'https://ipinfo.io/$ipAddress/json',
        'http://ip-api.com/json/$ipAddress',
      ];

      for (var endpoint in endpoints) {
        try {
          final response = await http
              .get(
                Uri.parse(endpoint),
              )
              .timeout(const Duration(seconds: 5));

          if (response.statusCode == 200) {
            final json = jsonDecode(response.body);

            // ipapi.co формат
            if (json['latitude'] != null && json['longitude'] != null) {
              final lat = json['latitude'] is double
                  ? json['latitude']
                  : double.tryParse(json['latitude'].toString());
              final lng = json['longitude'] is double
                  ? json['longitude']
                  : double.tryParse(json['longitude'].toString());

              if (lat != null && lng != null) {
                print('✅ IP хаягаар байршил олдлоо: $lat, $lng');
                return LatLng(lat, lng);
              }
            }

            // ipinfo.io формат (loc field: "lat,lng")
            if (json['loc'] != null) {
              final loc = json['loc'].toString().split(',');
              if (loc.length == 2) {
                final lat = double.tryParse(loc[0].trim());
                final lng = double.tryParse(loc[1].trim());
                if (lat != null && lng != null) {
                  print('✅ IP хаягаар байршил олдлоо (ipinfo.io): $lat, $lng');
                  return LatLng(lat, lng);
                }
              }
            }

            // ip-api.com формат
            if (json['lat'] != null && json['lon'] != null) {
              final lat = json['lat'] is double
                  ? json['lat']
                  : double.tryParse(json['lat'].toString());
              final lng = json['lon'] is double
                  ? json['lon']
                  : double.tryParse(json['lon'].toString());

              if (lat != null && lng != null) {
                print('✅ IP хаягаар байршил олдлоо (ip-api.com): $lat, $lng');
                return LatLng(lat, lng);
              }
            }
          }
        } catch (e) {
          print('⚠️ IP geolocation алдаа ($endpoint): $e');
          continue;
        }
      }

      print('❌ IP хаягаар байршил олдсонгүй');
      return null;
    } catch (e) {
      print('❌ IP geolocation ерөнхий алдаа: $e');
      return null;
    }
  }

  /// Try to get location with better error handling and timeout
  Future<void> updateCurrentLocation() async {
    try {
      // IP хаяг авах болон IP-аар байршлыг тодорхойлох
      _getIpAddress().then((ip) async {
        if (ip != null) {
          _currentIpAddress = ip;

          // IP хаягаар байршлыг тодорхойлох
          final ipLocation = await _getLocationFromIp(ip);
          if (ipLocation != null && _currentLocation == null) {
            // GPS байршил байхгүй бол IP-аар олсон байршлыг ашиглах
            _currentLocation = ipLocation;
            if (_shouldAddToHistory(_currentLocation!)) {
              _locationHistory.add(_currentLocation!);
            }
            _lastLocationUpdateTime = DateTime.now();
            await _saveLocations();
            print(
                '✅ IP хаягаар байршил тодорхойллоо: ${ipLocation.latitude}, ${ipLocation.longitude}');
            notifyListeners();
          }

          notifyListeners();
        }
      });

      // Check if location service is enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // GPS байхгүй бол IP-аар олсон байршлыг ашиглах
        if (_currentLocation == null) {
          // IP хаяг авах хүлээх
          await Future.delayed(const Duration(seconds: 2));
        }

        if (_currentLocation == null) {
          _errorMessage = 'Байршлын үйлчилгээ идэвхгүй байна.';
          notifyListeners();
          return;
        }
      }

      // Try with best accuracy first
      try {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.best,
          timeLimit: const Duration(seconds: 15),
          forceAndroidLocationManager: false,
        ).timeout(
          const Duration(seconds: 20),
        );

        if (pos.latitude != 0.0 && pos.longitude != 0.0) {
          _currentLocation = LatLng(pos.latitude, pos.longitude);
          if (_shouldAddToHistory(_currentLocation!)) {
            _locationHistory.add(_currentLocation!);
          }
          _lastLocationUpdateTime =
              DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
          _errorMessage = null;
          await _saveLocations();
          notifyListeners();
          return;
        }
      } catch (e) {
        print('Best accuracy GPS алдаа: $e');
      }

      // Try with medium accuracy as fallback
      try {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 10),
        ).timeout(
          const Duration(seconds: 15),
        );

        if (pos.latitude != 0.0 && pos.longitude != 0.0) {
          _currentLocation = LatLng(pos.latitude, pos.longitude);
          if (_shouldAddToHistory(_currentLocation!)) {
            _locationHistory.add(_currentLocation!);
          }
          _lastLocationUpdateTime =
              DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
          _errorMessage = null;
          await _saveLocations();
          notifyListeners();
          return;
        }
      } catch (e) {
        print('Medium accuracy GPS алдаа: $e');
      }

      // Try with low accuracy as last resort
      try {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 8),
        ).timeout(
          const Duration(seconds: 10),
        );

        if (pos.latitude != 0.0 && pos.longitude != 0.0) {
          _currentLocation = LatLng(pos.latitude, pos.longitude);
          if (_shouldAddToHistory(_currentLocation!)) {
            _locationHistory.add(_currentLocation!);
          }
          _lastLocationUpdateTime =
              DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
          _errorMessage = null;
          await _saveLocations();
          notifyListeners();
          return;
        }
      } catch (e) {
        print('Low accuracy GPS алдаа: $e');
      }

      // If all attempts fail, try last known position (works offline)
      try {
        Position? lastKnownPos = await Geolocator.getLastKnownPosition();
        if (lastKnownPos != null &&
            lastKnownPos.latitude != 0.0 &&
            lastKnownPos.longitude != 0.0) {
          _currentLocation =
              LatLng(lastKnownPos.latitude, lastKnownPos.longitude);
          if (_shouldAddToHistory(_currentLocation!)) {
            _locationHistory.add(_currentLocation!);
          }
          _lastLocationUpdateTime =
              DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
          await _saveLocations();
          _errorMessage =
              null; // Сүүлийн мэдэгдсэн байршил ашиглаж байгаа үед алдаа харуулахгүй
          notifyListeners();
          print(
              'Сүүлийн мэдэгдсэн байршил ашиглалаа: ${lastKnownPos.latitude}, ${lastKnownPos.longitude}');
          return;
        }
      } catch (e3) {
        print('Сүүлийн мэдэгдсэн байршил байхгүй: $e3');
      }

      // Try to use saved location from SharedPreferences
      if (_currentLocation != null) {
        _errorMessage =
            null; // Хадгалагдсан байршил ашиглаж байгаа үед алдаа харуулахгүй
        notifyListeners();
        print(
            'Хадгалагдсан байршил ашиглалаа: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
      } else {
        _errorMessage = 'GPS ажиллахгүй байна. Байршлын үйлчилгээг шалгана уу.';
        notifyListeners();
      }
    } catch (e) {
      print('Update location алдаа: $e');

      // Try last known position as fallback
      try {
        Position? lastKnownPos = await Geolocator.getLastKnownPosition();
        if (lastKnownPos != null &&
            lastKnownPos.latitude != 0.0 &&
            lastKnownPos.longitude != 0.0) {
          _currentLocation =
              LatLng(lastKnownPos.latitude, lastKnownPos.longitude);
          if (_shouldAddToHistory(_currentLocation!)) {
            _locationHistory.add(_currentLocation!);
          }
          _lastLocationUpdateTime =
              DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
          await _saveLocations();
          _errorMessage =
              null; // Сүүлийн мэдэгдсэн байршил ашиглаж байгаа үед алдаа харуулахгүй
          notifyListeners();
          return;
        }
      } catch (e2) {
        print('Сүүлийн мэдэгдсэн байршил авах алдаа: $e2');
      }

      _errorMessage = 'Байршил шинэчлэх алдаа: ${e.toString()}';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _locationUpdateTimer?.cancel();
    _backendSyncTimer?.cancel();
    super.dispose();
  }
}
