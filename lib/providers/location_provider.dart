import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:convert';

class LocationProvider extends ChangeNotifier {
  LatLng? _currentLocation;
  List<LatLng> _locationHistory = [];
  StreamSubscription<Position>? _positionSub;
  Timer? _locationUpdateTimer; // 2 секунд тутамд байршлыг шинэчлэх timer
  bool _isTracking = false;
  String? _errorMessage;
  bool _isLocationServiceEnabled = false;
  bool _useIpOnlyMode = false; // Зөвхөн IP хаягаар байршлыг тодорхойлох горим
  DateTime? _wakeTime; // Ассан цаг
  DateTime? _sleepTime; // Унтаасан цаг
  DateTime? _lastLocationUpdateTime; // GPS байршлын сүүлийн шинэчлэлтийн цаг
  String? _currentIpAddress; // Одоогийн IP хаяг
  static const double _minDistanceToSave = 20.0; // 20 метрийн хүрээ доторх хөдөлгөөнийг хадгалахгүй

  // Storage keys
  static const String _locationHistoryKey = 'location_history';
  static const String _currentLocationKey = 'current_location';
  static const String _wakeTimeKey = 'wake_time';
  static const String _sleepTimeKey = 'sleep_time';

  LocationProvider() {
    _loadSavedLocations();
    _loadSavedTimes();
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

  /// Зөвхөн IP горимд ажиллах (fallback горим)
  void setIpOnlyMode(bool enabled) {
    _useIpOnlyMode = enabled;
    if (enabled) {
      // GPS tracking-ийг зогсоох
      stopTracking();
      // IP-аар байршлыг тодорхойлох (fallback)
      _startIpOnlyTracking();
    } else {
      // GPS горим руу шилжих
      stopTracking();
      startTracking();
    }
    notifyListeners();
  }

  /// Зөвхөн IP хаягаар байршлыг тодорхойлох
  Future<void> _startIpOnlyTracking() async {
    try {
      _errorMessage = null;
      _isTracking = true;
      _isLocationServiceEnabled = false;
      _useIpOnlyMode = true; // IP-only горим идэвхжүүлэх
      
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
      
      // IP хаягийг тогтмол шинэчлэх (Google Maps My Location-ийн адил)
      // Эхлээд 10 секунд хүлээгээд, дараа нь 30 секунд тутамд шинэчлэх
      _locationUpdateTimer?.cancel();
      
      // Эхний шинэчлэлт (10 секунд хүлээгээд)
      Future.delayed(const Duration(seconds: 10), () async {
        if (_isTracking && _useIpOnlyMode) {
          final newIp = await _getIpAddress();
          if (newIp != null) {
            _currentIpAddress = newIp;
            final ipLocation = await _getLocationFromIp(newIp);
            if (ipLocation != null) {
              _currentLocation = ipLocation;
              if (_shouldAddToHistory(_currentLocation!)) {
                _locationHistory.add(_currentLocation!);
              }
              _lastLocationUpdateTime = DateTime.now();
              await _saveLocations();
              print('✅ IP хаягаар байршил шинэчлэгдлээ (эхний): ${ipLocation.latitude}, ${ipLocation.longitude}');
              notifyListeners();
            }
          }
        }
      });
      
      // Тогтмол шинэчлэлт (30 секунд тутамд)
      _locationUpdateTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
        if (!_isTracking || !_useIpOnlyMode) {
          timer.cancel();
          return;
        }
        
        final newIp = await _getIpAddress();
        if (newIp != null) {
          _currentIpAddress = newIp;
          final ipLocation = await _getLocationFromIp(newIp);
          if (ipLocation != null) {
            // Зөвхөн байршил мэдэгдэхүйц өөрчлөгдсөн тохиолдолд шинэчлэх
            if (_currentLocation == null || 
                Geolocator.distanceBetween(
                  _currentLocation!.latitude,
                  _currentLocation!.longitude,
                  ipLocation.latitude,
                  ipLocation.longitude,
                ) > 100) { // 100 метрээс их өөрчлөгдсөн бол шинэчлэх
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
        }
      });
    } catch (e) {
      print('❌ IP горим алдаа: $e');
      _errorMessage = 'IP горимд алдаа гарлаа: $e';
      notifyListeners();
    }
  }

  /// GPS ашиглан байршлыг тодорхойлох
  Future<void> _startGpsTracking() async {
    try {
      _errorMessage = null;
      
      // Байршлын эрхийг шалгах
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _errorMessage = 'Байршлын үйлчилгээ идэвхгүй байна. Тохиргоонд оруулж идэвхжүүлнэ үү.';
        _isLocationServiceEnabled = false;
        notifyListeners();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _errorMessage = 'Байршлын эрх татгалзсан байна.';
          _isLocationServiceEnabled = false;
          notifyListeners();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _errorMessage = 'Байршлын эрх татгалзсан байна. Тохиргоонд оруулж эрх олгоно уу.';
        _isLocationServiceEnabled = false;
        notifyListeners();
        return;
      }

      _isTracking = true;
      _isLocationServiceEnabled = true;
      _useIpOnlyMode = false;

      // Эхний байршлыг авах
      try {
        Position position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
        
        _currentLocation = LatLng(position.latitude, position.longitude);
        if (_shouldAddToHistory(_currentLocation!)) {
          _locationHistory.add(_currentLocation!);
        }
        _lastLocationUpdateTime = DateTime.now();
        await _saveLocations();
        print('✅ GPS байршил тодорхойллоо: ${position.latitude}, ${position.longitude}');
        _errorMessage = null;
        notifyListeners();
      } catch (e) {
        print('⚠️ Эхний GPS байршил авах алдаа: $e');
        // Алдаа гарвал stream-ээр авах гэж оролдох
      }

      // Байршлын өөрчлөлтийг stream-ээр сонсох
      _positionSub?.cancel();
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // 10 метрээс их хөдөлсөн тохиолдолд шинэчлэх
        ),
      ).listen(
        (Position position) {
          final newLocation = LatLng(position.latitude, position.longitude);
          
          // Зөвхөн байршил мэдэгдэхүйц өөрчлөгдсөн тохиолдолд шинэчлэх
          if (_currentLocation == null || 
              Geolocator.distanceBetween(
                _currentLocation!.latitude,
                _currentLocation!.longitude,
                newLocation.latitude,
                newLocation.longitude,
              ) > _minDistanceToSave) {
            _currentLocation = newLocation;
            if (_shouldAddToHistory(_currentLocation!)) {
              _locationHistory.add(_currentLocation!);
            }
            _lastLocationUpdateTime = DateTime.now();
            _saveLocations().catchError((e) {
              print('⚠️ Байршлыг хадгалах алдаа: $e');
            });
            print('✅ GPS байршил шинэчлэгдлээ: ${position.latitude}, ${position.longitude}');
            notifyListeners();
          }
        },
        onError: (error) {
          print('❌ GPS stream алдаа: $error');
          _errorMessage = 'GPS байршил авах алдаа: ${error.toString()}';
          notifyListeners();
        },
      );
    } catch (e) {
      print('❌ GPS горим алдаа: $e');
      _errorMessage = 'GPS горимд алдаа гарлаа: $e';
      _isTracking = false;
      _isLocationServiceEnabled = false;
      notifyListeners();
    }
  }

  Future<void> startTracking() async {
    // GPS ашиглан байршлыг тодорхойлох
    await _startGpsTracking();
  }

  void stopTracking() {
    // GPS tracking унтраах
    _isTracking = false;
    _positionSub?.cancel();
    _positionSub = null;
    _locationUpdateTimer?.cancel();
    _locationUpdateTimer = null;
    _useIpOnlyMode = false;
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

  /// IP хаягаар байршлыг тодорхойлох (Google Maps My Location зарчмыг ашиглаж сайжруулсан)
  Future<LatLng?> _getLocationFromIp(String ipAddress) async {
    try {
      // IP geolocation API endpoint-үүд (илүү нарийвчлалтай API-ууд эхэнд)
      // Олон API-уудыг туршиж, хамгийн нарийвчлалтай байршлыг авах
      final endpoints = [
        {
          'url': 'https://ipapi.co/$ipAddress/json/',
          'type': 'ipapi',
          'priority': 1, // Хамгийн өндөр түвшин
        },
        {
          'url': 'https://ip-api.com/json/$ipAddress',
          'type': 'ipapi_com',
          'priority': 2,
        },
        {
          'url': 'https://ipinfo.io/$ipAddress/json',
          'type': 'ipinfo',
          'priority': 3,
        },
        {
          'url': 'https://ipgeolocation.io/ipgeo/api?ip=$ipAddress',
          'type': 'ipgeolocation',
          'priority': 4,
        },
      ];
      
      // Priority дарааллаар эрэмбэлэх
      endpoints.sort((a, b) => (a['priority'] as int).compareTo(b['priority'] as int));
      
      LatLng? bestLocation;
      double? bestAccuracy;
      
      for (var endpoint in endpoints) {
        try {
          final response = await http.get(
            Uri.parse(endpoint['url'] as String),
            headers: {
              'Accept': 'application/json',
              'User-Agent': 'Mozilla/5.0',
            },
          ).timeout(const Duration(seconds: 8));
          
          if (response.statusCode == 200) {
            final json = jsonDecode(response.body);
            LatLng? location;
            double? accuracy;
            
            final type = endpoint['type'] as String;
            
            // ipapi.co формат (хамгийн нарийвчлалтай)
            if (type == 'ipapi') {
              if (json['latitude'] != null && json['longitude'] != null) {
                final lat = json['latitude'] is double 
                    ? json['latitude'] 
                    : double.tryParse(json['latitude'].toString());
                final lng = json['longitude'] is double 
                    ? json['longitude'] 
                    : double.tryParse(json['longitude'].toString());
                
                if (lat != null && lng != null) {
                  location = LatLng(lat, lng);
                  // Accuracy мэдээлэл байвал ашиглах
                  if (json['accuracy'] != null) {
                    accuracy = json['accuracy'] is double 
                        ? json['accuracy'] 
                        : double.tryParse(json['accuracy'].toString());
                  }
                  print('✅ IP хаягаар байршил олдлоо (ipapi.co): $lat, $lng');
                }
              }
            }
            
            // ip-api.com формат
            else if (type == 'ipapi_com') {
              if (json['lat'] != null && json['lon'] != null) {
                final lat = json['lat'] is double 
                    ? json['lat'] 
                    : double.tryParse(json['lat'].toString());
                final lng = json['lon'] is double 
                    ? json['lon'] 
                    : double.tryParse(json['lon'].toString());
                
                if (lat != null && lng != null) {
                  location = LatLng(lat, lng);
                  print('✅ IP хаягаар байршил олдлоо (ip-api.com): $lat, $lng');
                }
              }
            }
            
            // ipinfo.io формат (loc field: "lat,lng")
            else if (type == 'ipinfo') {
              if (json['loc'] != null) {
                final loc = json['loc'].toString().split(',');
                if (loc.length == 2) {
                  final lat = double.tryParse(loc[0].trim());
                  final lng = double.tryParse(loc[1].trim());
                  if (lat != null && lng != null) {
                    location = LatLng(lat, lng);
                    print('✅ IP хаягаар байршил олдлоо (ipinfo.io): $lat, $lng');
                  }
                }
              }
            }
            
            // ipgeolocation.io формат
            else if (type == 'ipgeolocation') {
              if (json['latitude'] != null && json['longitude'] != null) {
                final lat = json['latitude'] is double 
                    ? json['latitude'] 
                    : double.tryParse(json['latitude'].toString());
                final lng = json['longitude'] is double 
                    ? json['longitude'] 
                    : double.tryParse(json['longitude'].toString());
                
                if (lat != null && lng != null) {
                  location = LatLng(lat, lng);
                  print('✅ IP хаягаар байршил олдлоо (ipgeolocation.io): $lat, $lng');
                }
              }
            }
            
            // Хамгийн нарийвчлалтай байршлыг сонгох
            if (location != null) {
              bool shouldUpdate = false;
              if (bestLocation == null) {
                shouldUpdate = true;
              } else if (accuracy != null) {
                if (bestAccuracy == null || accuracy < bestAccuracy) {
                  shouldUpdate = true;
                }
              }
              
              if (shouldUpdate) {
                bestLocation = location;
                bestAccuracy = accuracy;
                // Хамгийн нарийвчлалтай байршил олдвол зогсох
                if (accuracy != null && accuracy < 1000) { // 1км-ээс бага алдаатай бол зогсох
                  break;
                }
              }
            }
          }
        } catch (e) {
          print('⚠️ IP geolocation алдаа (${endpoint['url']}): $e');
          continue;
        }
      }
      
      if (bestLocation != null) {
        print('✅ IP хаягаар эцсийн байршил: ${bestLocation.latitude}, ${bestLocation.longitude}');
        return bestLocation;
      }
      
      print('❌ IP хаягаар байршил олдсонгүй');
      return null;
    } catch (e) {
      print('❌ IP geolocation ерөнхий алдаа: $e');
      return null;
    }
  }

  /// GPS ашиглан байршлыг шинэчлэх
  Future<void> updateCurrentLocation() async {
    try {
      _errorMessage = null;
      
      // Байршлын эрхийг шалгах
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _errorMessage = 'Байршлын үйлчилгээ идэвхгүй байна.';
        _isLocationServiceEnabled = false;
        notifyListeners();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _errorMessage = 'Байршлын эрх татгалзсан байна.';
          _isLocationServiceEnabled = false;
          notifyListeners();
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _errorMessage = 'Байршлын эрх татгалзсан байна. Тохиргоонд оруулж эрх олгоно уу.';
        _isLocationServiceEnabled = false;
        notifyListeners();
        return;
      }

      _isLocationServiceEnabled = true;

      // GPS байршлыг авах
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
      
      final newLocation = LatLng(position.latitude, position.longitude);
      _currentLocation = newLocation;
      if (_shouldAddToHistory(_currentLocation!)) {
        _locationHistory.add(_currentLocation!);
      }
      _lastLocationUpdateTime = DateTime.now();
      await _saveLocations();
      print('✅ GPS байршил шинэчлэгдлээ: ${position.latitude}, ${position.longitude}');
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      print('Update location алдаа: $e');
      _errorMessage = 'Байршил шинэчлэх алдаа: ${e.toString()}';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _locationUpdateTimer?.cancel();
    super.dispose();
  }
}
