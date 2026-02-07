import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import '../../providers/mobileUserLogin.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../widgets/hamburger_menu.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  Timer? _countdownTimer;
  
  @override
  void initState() {
    super.initState();
    // Listen to login provider changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final loginProvider = Provider.of<MobileUserLoginProvider>(context, listen: false);
      loginProvider.addListener(_onLoginProviderChanged);
      _startCountdownTimer(loginProvider);
    });
  }
  
  @override
  void dispose() {
    _countdownTimer?.cancel();
    final loginProvider = Provider.of<MobileUserLoginProvider>(context, listen: false);
    loginProvider.removeListener(_onLoginProviderChanged);
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
  
  void _onLoginProviderChanged() {
    if (mounted) {
      final loginProvider = Provider.of<MobileUserLoginProvider>(context, listen: false);
      setState(() {
        _isLoading = loginProvider.isLoading;
      });
      _startCountdownTimer(loginProvider);
    }
  }
  
  void _startCountdownTimer(MobileUserLoginProvider loginProvider) {
    _countdownTimer?.cancel();
    
    if (!loginProvider.canAttemptLogin && loginProvider.rateLimitUntil != null) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          final canAttempt = loginProvider.canAttemptLogin;
          if (canAttempt) {
            timer.cancel();
            setState(() {}); // Refresh UI when unblocked
          } else {
            setState(() {}); // Update countdown every second
          }
        } else {
          timer.cancel();
        }
      });
    }
  }


  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final loginProvider = Provider.of<MobileUserLoginProvider>(context, listen: false);
    
    // Check if login is blocked due to rate limiting
    if (!loginProvider.canAttemptLogin) {
      final rateLimitUntil = loginProvider.rateLimitUntil;
      if (rateLimitUntil != null) {
        final waitSeconds = rateLimitUntil.difference(DateTime.now()).inSeconds;
        final waitMinutes = (waitSeconds / 60).ceil();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(waitSeconds >= 60 
                ? 'Хэт олон оролдлого хийсэн. Та $waitMinutes минут хүлээгээд дахин оролдоно уу.'
                : 'Хэт олон оролдлого хийсэн. Та $waitSeconds секунд хүлээгээд дахин оролдоно уу.'),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    
    final success = await loginProvider.login(
      identifier: _emailController.text.trim(),
      password: _passwordController.text,
      authProvider: authProvider,
    );

    setState(() {
      _isLoading = false;
    });

    if (mounted) {
      if (success) {
        // Connect to warehouse backend and fetch data
        try {
          final warehouseProvider = Provider.of<WarehouseProvider>(context, listen: false);
          await warehouseProvider.connect(
            identifier: _emailController.text.trim(),
            password: _passwordController.text,
            authProvider: authProvider,
          );
          
          // Fetch products and shops from warehouse
          await warehouseProvider.refreshProducts();
          await warehouseProvider.refreshShops(authProvider: authProvider);
        } catch (e) {
          // Continue even if warehouse connection fails
          debugPrint('Warehouse connection failed: $e');
        }
        
        // Login succeeded -> start location tracking immediately (asks permission if needed)
        // Avoid auto-prompt on web unless explicitly desired.
        if (!kIsWeb) {
          await Provider.of<LocationProvider>(context, listen: false).startTracking();
        }

        final role = authProvider.userRole;
        if (role == 'order') {
          context.go('/order-screen');
        } else {
          context.go('/sales-dashboard');
        }
      } else {
        // Show error from loginProvider
        final errorMessage = loginProvider.error ?? 'Нэвтрэх үед алдаа гарлаа. Дахин оролдоно уу.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        backgroundColor: const Color(0xFF6366F1),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
      ),
      drawer: const HamburgerMenu(),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF6366F1),
              Color(0xFF8B5CF6),
              Color(0xFF06B6D4),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Card(
                  elevation: 8,
                  shadowColor: Colors.black.withOpacity(0.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32.0),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Logo/Title Section
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF6366F1).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.business_center_rounded,
                              size: 60,
                              color: Color(0xFF6366F1),
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          Text(
                            'Welcome Back',
                            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: const Color(0xFF1E293B),
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          
                          Text(
                            'Sign in to your Oasis Business account',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: const Color(0xFF1E293B),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),

                          // Email Field
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email Address',
                              hintText: 'Enter your email',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!value.contains('@')) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),

                          // Password Field
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              hintText: 'Enter your password',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your password';
                              }
                              if (value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 32),

                          // Login Button
                          Consumer<MobileUserLoginProvider>(
                            builder: (context, loginProvider, _) {
                              final isBlocked = !loginProvider.canAttemptLogin;
                              final rateLimitUntil = loginProvider.rateLimitUntil;
                              String? waitMessage;
                              
                              if (isBlocked && rateLimitUntil != null) {
                                final waitSeconds = rateLimitUntil.difference(DateTime.now()).inSeconds;
                                if (waitSeconds > 0) {
                                  if (waitSeconds >= 60) {
                                    final minutes = (waitSeconds / 60).ceil();
                                    waitMessage = '$minutes минут хүлээх';
                                  } else {
                                    waitMessage = '$waitSeconds секунд хүлээх';
                                  }
                                }
                              }
                              
                              return SizedBox(
                                width: double.infinity,
                                height: 56,
                                child: ElevatedButton(
                                  onPressed: (_isLoading || isBlocked) ? null : _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6366F1),
                                    foregroundColor: Colors.white,
                                    elevation: 3,
                                    shadowColor: const Color(0xFF6366F1).withOpacity(0.4),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: _isLoading
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          waitMessage ?? 'Sign In',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 24),


                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

}
