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

  Future<bool> login(String email, String password) async {
    try {
      // Simulate API call
      await Future.delayed(const Duration(seconds: 1));
      
      // Mock login logic - in real app, call your API
      if (email == 'sales@company.com' && password == 'sales123') {
        _user = User(
          id: '1',
          name: 'Sales Staff',
          email: email,
          role: 'sales',
          companyId: 'company1',
          createdAt: DateTime.now(),
        );
        _userRole = 'sales';
        _isLoggedIn = true;
        
        await _saveUserData();
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }


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
}
