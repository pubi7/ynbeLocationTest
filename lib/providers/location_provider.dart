import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';
import '../config/api_config.dart';

class LocationProvider extends ChangeNotifier {
  LatLng? _currentLocation;
  List<LatLng> _locationHistory = [];
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
  static const double _minDistanceToSave = 20.0; // 20 метрийн хүрээ доторх хөдөлгөөнийг хадгалахгүй
  int? _currentAgentId; // Одоогийн борлуулагчийн ID

  // Storage keys
  static const String _locationHistoryKey = 'location_history';
  static const String _currentLocationKey = 'current_location';
  static const String _wakeTimeKey = 'wake_time';
  static const String _sleepTimeKey = 'sleep_time';
  static const String _autoStartLocationKey = 'auto_start_location_tracking';
  bool _autoStartEnabled = true;

  LocationProvider() {
    _loadSavedLocations();
    _loadSavedTimes();
    _loadAutoStartPref();
    _loadAgentId();
  }

  /// Load agent ID from SharedPreferences
  Future<void> _loadAgentId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _currentAgentId = prefs.getInt('agent_id');
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
      await prefs.setInt('agent_id', agentId);
      print('✅ Agent ID хадгалагдлаа: $agentId');
    } catch (e) {
      print('Алдаа: Agent ID хадгалах: $e');
    }
    notifyListeners();
  }

  /// Send location to backend
  Future<bool> _sendLocationToBackend(LatLng location) async {
    if (_currentAgentId == null) {
      print('⚠️  Agent ID байхгүй, backend руу илгээх боломжгүй');
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');

      if (token == null) {
        print('⚠️  Auth token байхгүй');
        return false;
      }

      final url = Uri.parse('${ApiConfig.backendServerUrl}/api/agents/$_currentAgentId/location');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'latitude': location.latitude,
          'longitude': location.longitude,
          'ipAddress': _currentIpAddress,
          'accuracy': 10.0, // Default accuracy
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 201) {
        print('✅ Байршил backend руу илгээгдлээ: ${location.latitude}, ${location.longitude}');
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

  /// Start periodic backend sync (every 2 minutes)
  void _startBackendSync() {
    _backendSyncTimer?.cancel();
    _backendSyncTimer = Timer.periodic(
      const Duration(minutes: 2),
      (Timer timer) async {
        if (_isTracking && _currentLocation != null) {
          await _sendLocationToBackend(_currentLocation!);
        }
      },
    );
    print('🔄 Backend sync эхлүүлэгдлээ (2 минут тутамд)');
  }

  LatLng? get currentLocation => _currentLocation;
  List<LatLng> get locationHistory => _locationHistory;
  bool get isTracking => _isTracking;
  String? get errorMessage => _errorMessage;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;
  bool get useIpOnlyMode => _useIpOnlyMode; // Зөвхөн IP горим
  DateTime? get wakeTime => _wakeTime; // Ассан цаг
  DateTime? get sleepTime => _sleepTime; // Унтаасан цаг
  DateTime? get lastLocationUpdateTime => _lastLocationUpdateTime; // GPS байршлын сүүлийн шинэчлэлтийн цаг
  String? get currentIpAddress => _currentIpAddress; // Одоогийн IP хаяг
  bool get autoStartEnabled => _autoStartEnabled;

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
      print('Байршил 20 метрээс ойр тул хадгалахгүй: ${distance.toStringAsFixed(2)}м');
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
        final Map<String, dynamic> locationMap = jsonDecode(currentLocationJson);
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
          print('✅ IP хаягаар байршил тодорхойллоо: ${ipLocation.latitude}, ${ipLocation.longitude}');
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
      _locationUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
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
            print('✅ IP хаягаар байршил шинэчлэгдлээ: ${ipLocation.latitude}, ${ipLocation.longitude}');
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
            print('✅ IP хаягаар байршил тодорхойллоо: ${ipLocation.latitude}, ${ipLocation.longitude}');
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
          if (lastKnownPos != null && lastKnownPos.latitude != 0.0 && lastKnownPos.longitude != 0.0) {
            _currentLocation = LatLng(lastKnownPos.latitude, lastKnownPos.longitude);
            if (_shouldAddToHistory(_currentLocation!)) {
              _locationHistory.add(_currentLocation!);
            }
            _lastLocationUpdateTime = DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
            await _saveLocations();
            _isTracking = true;
            _isLocationServiceEnabled = false;
            _errorMessage = null; // Сүүлийн мэдэгдсэн байршил ашиглаж байгаа үед алдаа харуулахгүй
            notifyListeners();
            print('Офлайн горим: Сүүлийн мэдэгдсэн байршил ашиглалаа: ${lastKnownPos.latitude}, ${lastKnownPos.longitude}');
            return;
          }
        } catch (e) {
          print('Офлайн горимд сүүлийн байршил авах алдаа: $e');
        }
        
        // Try to use saved location
        if (_currentLocation != null) {
          _isTracking = true;
          _isLocationServiceEnabled = false;
          _errorMessage = null; // Хадгалагдсан байршил ашиглаж байгаа үед алдаа харуулахгүй
          notifyListeners();
          print('Офлайн горим: Хадгалагдсан байршил ашиглалаа: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
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
          _errorMessage = null; // IP-аар олсон байршил ашиглаж байгаа үед алдаа харуулахгүй
          notifyListeners();
          print('Офлайн горим: IP хаягаар байршил тодорхойллоо: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
          return;
        }
        
        _errorMessage = 'Байршлын үйлчилгээ идэвхгүй байна. Тохиргооноос идэвхжүүлнэ үү.';
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
        _errorMessage = 'Байршлын зөвшөөрөл олгоогүй. Тохиргооноос зөвшөөрнө үү.';
        notifyListeners();
        return;
      }
      
      if (permission == LocationPermission.deniedForever) {
        _errorMessage = 'Байршлын зөвшөөрөл бүрэн хориглогдсон. Тохиргооноос дахин идэвхжүүлнэ үү.';
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
          _lastLocationUpdateTime = DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
          await _saveLocations();
          _errorMessage = null;
          notifyListeners();
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
            _currentLocation = LatLng(currentPos.latitude, currentPos.longitude);
            if (_shouldAddToHistory(_currentLocation!)) {
              _locationHistory.add(_currentLocation!);
            }
            _lastLocationUpdateTime = DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
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
            if (lastKnownPos != null && lastKnownPos.latitude != 0.0 && lastKnownPos.longitude != 0.0) {
              _currentLocation = LatLng(lastKnownPos.latitude, lastKnownPos.longitude);
              if (_shouldAddToHistory(_currentLocation!)) {
                _locationHistory.add(_currentLocation!);
              }
              _lastLocationUpdateTime = DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
              await _saveLocations();
              _errorMessage = null; // Сүүлийн мэдэгдсэн байршил ашиглаж байгаа үед алдаа харуулахгүй
              notifyListeners();
              print('Сүүлийн мэдэгдсэн байршил ашиглалаа: ${lastKnownPos.latitude}, ${lastKnownPos.longitude}');
            } else {
              throw Exception('Last known position not available');
            }
          } catch (e3) {
            print('Сүүлийн мэдэгдсэн байршил байхгүй: $e3');
            
            // Try to use saved location from SharedPreferences
            if (_currentLocation != null) {
              _errorMessage = null; // Хадгалагдсан байршил ашиглаж байгаа үед алдаа харуулахгүй
              notifyListeners();
              print('Хадгалагдсан байршил ашиглалаа: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
            } else {
              _errorMessage = 'GPS оффлайн байна. Түр зуурын байршил ашиглаж байна.';
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
      _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
          (Position pos) {
            if (pos.latitude != 0.0 && pos.longitude != 0.0) {
              final newLocation = LatLng(pos.latitude, pos.longitude);
              
              _currentLocation = newLocation;
              
              // 20 метрийн хүрээ доторх хөдөлгөөнийг хадгалахгүй
              if (_shouldAddToHistory(_currentLocation!)) {
                _locationHistory.add(_currentLocation!);
              }
              
              _lastLocationUpdateTime = DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
              _errorMessage = null; // Clear error when we get location
              _saveLocations();
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
      
      // Start timer to save location every 1 minute (ensure data persistence)
      _locationUpdateTimer?.cancel();
      _locationUpdateTimer = Timer.periodic(
        const Duration(minutes: 1),
        (Timer timer) async {
          if (_isTracking && _currentLocation != null) {
            try {
              // Хэрэв байршил байгаа бол хадгалах
              await _saveLocations();
              print('GPS байршил 1 минут тутамд хадгалагдлаа');
            } catch (e) {
              print('Timer байршил хадгалах алдаа: $e');
            }
          } else if (!_isTracking) {
            timer.cancel();
          }
        },
      );
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
          final response = await http.get(
            Uri.parse(endpoint),
          ).timeout(const Duration(seconds: 5));
          
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
              if (RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(body)) {
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
          final response = await http.get(
            Uri.parse(endpoint),
          ).timeout(const Duration(seconds: 5));
          
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
            print('✅ IP хаягаар байршил тодорхойллоо: ${ipLocation.latitude}, ${ipLocation.longitude}');
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
          _lastLocationUpdateTime = DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
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
          _lastLocationUpdateTime = DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
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
          _lastLocationUpdateTime = DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
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
        if (lastKnownPos != null && lastKnownPos.latitude != 0.0 && lastKnownPos.longitude != 0.0) {
          _currentLocation = LatLng(lastKnownPos.latitude, lastKnownPos.longitude);
          if (_shouldAddToHistory(_currentLocation!)) {
            _locationHistory.add(_currentLocation!);
          }
          _lastLocationUpdateTime = DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
          await _saveLocations();
          _errorMessage = null; // Сүүлийн мэдэгдсэн байршил ашиглаж байгаа үед алдаа харуулахгүй
          notifyListeners();
          print('Сүүлийн мэдэгдсэн байршил ашиглалаа: ${lastKnownPos.latitude}, ${lastKnownPos.longitude}');
          return;
        }
      } catch (e3) {
        print('Сүүлийн мэдэгдсэн байршил байхгүй: $e3');
      }
      
      // Try to use saved location from SharedPreferences
      if (_currentLocation != null) {
        _errorMessage = null; // Хадгалагдсан байршил ашиглаж байгаа үед алдаа харуулахгүй
        notifyListeners();
        print('Хадгалагдсан байршил ашиглалаа: ${_currentLocation!.latitude}, ${_currentLocation!.longitude}');
      } else {
        _errorMessage = 'GPS ажиллахгүй байна. Байршлын үйлчилгээг шалгана уу.';
        notifyListeners();
      }
    } catch (e) {
      print('Update location алдаа: $e');
      
      // Try last known position as fallback
      try {
        Position? lastKnownPos = await Geolocator.getLastKnownPosition();
        if (lastKnownPos != null && lastKnownPos.latitude != 0.0 && lastKnownPos.longitude != 0.0) {
          _currentLocation = LatLng(lastKnownPos.latitude, lastKnownPos.longitude);
          if (_shouldAddToHistory(_currentLocation!)) {
            _locationHistory.add(_currentLocation!);
          }
          _lastLocationUpdateTime = DateTime.now(); // Шинэчлэлтийн цагийг тэмдэглэх
          await _saveLocations();
          _errorMessage = null; // Сүүлийн мэдэгдсэн байршил ашиглаж байгаа үед алдаа харуулахгүй
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
