import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';

class AuthProvider extends ChangeNotifier {
  User? _user;
  bool _isLoggedIn = false;
  String _userRole = '';

  User? get user => _user;
  bool get isLoggedIn => _isLoggedIn;
  String get userRole => _userRole;

  AuthProvider() {
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userData = prefs.getString('user_data');
    if (userData != null) {
      // In a real app, you would parse the user data from JSON
      _isLoggedIn = true;
      _userRole = prefs.getString('user_role') ?? '';
      notifyListeners();
    }
  }

  // Login functionality has been moved to MobileUserLoginProvider
  // This provider now only stores and provides user data
  // Use MobileUserLoginProvider.login() for authentication


  Future<void> _saveUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_data', _user!.toJson().toString());
    await prefs.setString('user_role', _userRole);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_data');
    await prefs.remove('user_role');
    
    _user = null;
    _isLoggedIn = false;
    _userRole = '';
    notifyListeners();
  }

  /// Update user data from backend profile
  Future<void> updateFromBackend({
    required String id,
    required String name,
    required String email,
    required String role,
  }) async {
    _user = User(
      id: id,
      name: name,
      email: email,
      role: role,
      companyId: 'warehouse1',
      createdAt: DateTime.now(),
    );
    _userRole = role;
    _isLoggedIn = true;
    
    await _saveUserData();
    notifyListeners();
  }
}
