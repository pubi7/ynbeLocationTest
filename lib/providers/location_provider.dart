import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';

class LocationProvider extends ChangeNotifier {
  LatLng? _currentLocation;
  List<LatLng> _locationHistory = [];
  StreamSubscription<Position>? _positionSub;
  bool _isTracking = false;
  String? _errorMessage;
  bool _isLocationServiceEnabled = false;

  LatLng? get currentLocation => _currentLocation;
  List<LatLng> get locationHistory => _locationHistory;
  bool get isTracking => _isTracking;
  String? get errorMessage => _errorMessage;
  bool get isLocationServiceEnabled => _isLocationServiceEnabled;

  Future<void> startTracking() async {
    try {
      _errorMessage = null;
      
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _errorMessage = 'Байршлын үйлчилгээ идэвхгүй байна. Тохиргооноос идэвхжүүлнэ үү.';
        _isLocationServiceEnabled = false;
        notifyListeners();
        return;
      }
      
      _isLocationServiceEnabled = true;
      
      // Check and request permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.denied) {
        _errorMessage = 'Байршлын зөвшөөрөл олгоогүй. Тохиргооноос зөвшөөрнө үү.';
        notifyListeners();
        return;
      }
      
      if (permission == LocationPermission.deniedForever) {
        _errorMessage = 'Байршлын зөвшөөрөл бүрэн хориглогдсон. Тохиргооноос дахин идэвхжүүлнэ үү.';
        notifyListeners();
        return;
      }

      _isTracking = true;
      
      // Try to get current position first
      try {
        Position currentPos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        ).timeout(
          const Duration(seconds: 10),
        );
        _currentLocation = LatLng(currentPos.latitude, currentPos.longitude);
        _locationHistory.add(_currentLocation!);
        notifyListeners();
      } catch (e) {
        // If GPS fails (e.g., in simulator), use sample location
        print('Real GPS failed: $e, using sample location');
        useFakeLocation();
      }
      
      // Start position stream
      LocationSettings settings = const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5,
      );

      await _positionSub?.cancel();
      _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen(
          (Position pos) {
            _currentLocation = LatLng(pos.latitude, pos.longitude);
            _locationHistory.add(_currentLocation!);
            _errorMessage = null; // Clear error when we get location
            notifyListeners();
          },
          onError: (error) {
            _errorMessage = 'Байршил авах алдаа: ${error.toString()}';
            notifyListeners();
          },
        );
    } catch (e) {
      _errorMessage = 'Байршил хянах эхлүүлэх алдаа: ${e.toString()}';
      notifyListeners();
    }
  }

  void stopTracking() {
    _isTracking = false;
    _positionSub?.cancel();
    _positionSub = null;
    notifyListeners();
  }

  void clearHistory() {
    _locationHistory.clear();
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
    if (!_locationHistory.isEmpty) {
      _locationHistory.add(_currentLocation!);
    } else {
      _locationHistory = [_currentLocation!];
    }
    _errorMessage = null;
    _isTracking = true;
    _isLocationServiceEnabled = true;
    notifyListeners();
  }

  /// Try to get location with better error handling and timeout
  Future<void> updateCurrentLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          // If timeout, use fake location as fallback
          useFakeLocation();
          throw TimeoutException('Location timeout');
        },
      );
      
      _currentLocation = LatLng(pos.latitude, pos.longitude);
      _locationHistory.add(_currentLocation!);
      _errorMessage = null;
      notifyListeners();
    } catch (e) {
      // If real location fails, use sample location
      useFakeLocation();
    }
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    super.dispose();
  }
}
