import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/mobileUserLogin.dart';
import '../../providers/auth_provider.dart';
import '../../providers/location_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../providers/shop_provider.dart';
import '../../config/api_config.dart';
import '../../providers/product_provider.dart';
import '../../services/biometric_auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverUrlController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  Timer? _countdownTimer;

  bool _rememberMe = true;
  bool _biometricEnabled = false;
  bool _biometricSupported = false;
  bool _hasSavedToken = false;
  bool _biometricAutoPrompted = false;
  bool _hideIdentifierField = false;
  String? _savedIdentifier;

  @override
  void initState() {
    super.initState();
    _loadSavedServerUrl();
    _loadRememberAndBiometricPrefs();
    // Listen to login provider changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // WarehouseProvider-г эхлүүлж, хадгалагдсан Server URL ачаална (утаснаас localhost ажиллахгүй)
      Provider.of<WarehouseProvider>(context, listen: false);
      final loginProvider =
          Provider.of<MobileUserLoginProvider>(context, listen: false);
      loginProvider.addListener(_onLoginProviderChanged);
      _startCountdownTimer(loginProvider);

      // Auto prompt biometric on app start (login screen) when enabled + token exists.
      // This runs once per screen lifecycle to avoid repeated prompts.
      _maybeAutoPromptBiometric();
    });
  }

  Future<void> _maybeAutoPromptBiometric() async {
    if (_biometricAutoPrompted) return;
    _biometricAutoPrompted = true;

    // Wait for prefs load to complete (best-effort); don't block UI.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    if (!_rememberMe) return;
    if (!_biometricSupported || !_biometricEnabled || !_hasSavedToken) return;
    if (_isLoading) return;

    // Small delay so first frame is painted before system dialog.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    if (!mounted) return;
    await _loginWithBiometrics();
  }

  Future<void> _loadRememberAndBiometricPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _rememberMe = prefs.getBool('remember_me') ?? true;
      _biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
      final token = prefs.getString('warehouse_token');
      _hasSavedToken = token != null && token.trim().isNotEmpty;
      _savedIdentifier = prefs.getString('last_login_identifier')?.trim();
      if (_rememberMe &&
          _savedIdentifier != null &&
          _savedIdentifier!.isNotEmpty) {
        _emailController.text = _savedIdentifier!;
        _hideIdentifierField = true;
      } else {
        _hideIdentifierField = false;
      }
      _biometricSupported = await BiometricAuthService.isSupported();
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveBiometricEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_enabled', v);
  }

  Future<void> _loginWithBiometrics() async {
    if (!_biometricSupported || !_biometricEnabled || !_hasSavedToken) return;
    final ok = await BiometricAuthService.authenticate(
        reason: 'Хурууны хээгээр нэвтрэх');
    if (!ok || !mounted) return;

    // After biometric success, connect providers using existing token and route.
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final loginProvider =
        Provider.of<MobileUserLoginProvider>(context, listen: false);
    final warehouseProvider =
        Provider.of<WarehouseProvider>(context, listen: false);
    final shopProvider = Provider.of<ShopProvider>(context, listen: false);
    final productProvider =
        Provider.of<ProductProvider>(context, listen: false);

    setState(() => _isLoading = true);
    try {
      await _applyLoginServerUrl();
      await loginProvider.applyRememberMe(true);
      await warehouseProvider.connectWithExistingToken(
          authProvider: authProvider);
      await warehouseProvider.refreshProducts();
      await warehouseProvider.refreshShops(authProvider: authProvider);
      shopProvider.setShops(warehouseProvider.shops);
      productProvider.setProducts(warehouseProvider.products);

      if (!kIsWeb) {
        final locationProvider =
            Provider.of<LocationProvider>(context, listen: false);
        final agentId = loginProvider.user?.id ?? authProvider.user?.id;
        if (agentId != null) {
          final agentIdInt = int.tryParse(agentId);
          if (agentIdInt != null) {
            await locationProvider.setAgentId(agentIdInt);
          }
        }
        await locationProvider.startTracking();
      }

      final role = authProvider.userRole;
      if (role == 'order') {
        context.go('/order-screen');
      } else {
        // Non-order roles: go to dashboard first
        context.go('/sales-dashboard');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Хурууны хээгээр нэвтрэхэд алдаа: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSavedServerUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getString('warehouse_api_base_url');
      if (v != null && v.trim().isNotEmpty) {
        // Strip /api suffix for display
        String display = v.trim();
        if (display.toLowerCase().endsWith('/api')) {
          display = display.substring(0, display.length - 4);
        }
        if (mounted) {
          _serverUrlController.text = display;
        }
      } else if (mounted) {
        _serverUrlController.text = ApiConfig.defaultBackendServerUrl;
      }
    } catch (_) {}
  }

  /// Нэвтрэх / biometric-ийн өмнө shared bridge + SharedPreferences-д Server URL хадгална.
  Future<void> _applyLoginServerUrl() async {
    var raw = _serverUrlController.text.trim();
    if (raw.isEmpty) {
      raw = ApiConfig.defaultBackendServerUrl;
      if (mounted) {
        setState(() => _serverUrlController.text = raw);
      }
    }
    final warehouseProvider =
        Provider.of<WarehouseProvider>(context, listen: false);
    await warehouseProvider.updateApiBaseUrl(raw);
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    final loginProvider =
        Provider.of<MobileUserLoginProvider>(context, listen: false);
    loginProvider.removeListener(_onLoginProviderChanged);
    _emailController.dispose();
    _passwordController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  void _onLoginProviderChanged() {
    if (mounted) {
      final loginProvider =
          Provider.of<MobileUserLoginProvider>(context, listen: false);
      setState(() {
        _isLoading = loginProvider.isLoading;
      });
      _startCountdownTimer(loginProvider);
    }
  }

  void _startCountdownTimer(MobileUserLoginProvider loginProvider) {
    _countdownTimer?.cancel();

    if (!loginProvider.canAttemptLogin &&
        loginProvider.rateLimitUntil != null) {
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
    // When identifier is "remembered", only validate password (and server url).
    if (_hideIdentifierField) {
      final pwd = _passwordController.text.trim();
      if (pwd.isEmpty || pwd.length < 6) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нууц үгээ оруулна уу'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    } else {
      if (!_formKey.currentState!.validate()) return;
    }

    final loginProvider =
        Provider.of<MobileUserLoginProvider>(context, listen: false);

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

    try {
      await _applyLoginServerUrl();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Server URL тохируулахад алдаа: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final identifier = _emailController.text.trim();
    final success = await loginProvider.login(
      identifier: identifier,
      password: _passwordController.text,
      authProvider: authProvider,
    );

    setState(() {
      _isLoading = false;
    });

    if (mounted) {
      if (success) {
        await loginProvider.applyRememberMe(_rememberMe);
        final prefs = await SharedPreferences.getInstance();
        if (_rememberMe && identifier.isNotEmpty) {
          await prefs.setString('last_login_identifier', identifier);
        } else {
          await prefs.remove('last_login_identifier');
        }
        // Re-check token presence for biometric button visibility
        await _loadRememberAndBiometricPrefs();

        // Connect WarehouseProvider using the SAME token from MobileUserLoginProvider
        // (shared WarehouseWebBridge — no double login API call needed)
        try {
          final warehouseProvider =
              Provider.of<WarehouseProvider>(context, listen: false);
          final shopProvider =
              Provider.of<ShopProvider>(context, listen: false);
          final productProvider =
              Provider.of<ProductProvider>(context, listen: false);

          await warehouseProvider.connectWithExistingToken(
            authProvider: authProvider,
          );

          // Fetch products and shops from warehouse backend
          // Backend returns only the shops assigned to the logged-in user (no mock data)
          await warehouseProvider.refreshProducts();
          await warehouseProvider.refreshShops(authProvider: authProvider);

          // Sync to ShopProvider & ProductProvider so all screens see real data
          shopProvider.setShops(warehouseProvider.shops);
          productProvider.setProducts(warehouseProvider.products);

          if (kDebugMode) {
            debugPrint('✅ WarehouseProvider connected with mobile user token');
            debugPrint('   Mobile user ID: ${loginProvider.user?.id}');
            debugPrint(
                '   Shops (бүртгэлтэй дэлгүүр): ${warehouseProvider.shops.length}');
            debugPrint('   Products: ${warehouseProvider.products.length}');
          }
        } catch (e) {
          // Continue even if warehouse connection fails
          debugPrint('Warehouse connection failed: $e');
        }

        // Login succeeded -> set agent_id & start location tracking (location → backend → Weve site)
        // Avoid auto-prompt on web unless explicitly desired.
        if (!kIsWeb) {
          final locationProvider =
              Provider.of<LocationProvider>(context, listen: false);
          final agentId = loginProvider.user?.id ?? authProvider.user?.id;
          if (agentId != null) {
            final agentIdInt = int.tryParse(agentId);
            if (agentIdInt != null) {
              await locationProvider.setAgentId(agentIdInt);
            }
          }
          await locationProvider.startTracking();
        }

        final role = authProvider.userRole;
        if (role == 'order') {
          context.go('/order-screen');
        } else {
          // Non-order roles: go to dashboard first
          context.go('/sales-dashboard');
        }
      } else {
        // Show error from loginProvider
        final errorMessage = loginProvider.error ??
            'Нэвтрэх үед алдаа гарлаа. Дахин оролдоно уу.';
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
      ),
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
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(
                                  color: const Color(0xFF1E293B),
                                  fontWeight: FontWeight.bold,
                                ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),

                          Text(
                            'Sign in to your Oasis Business account',
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: const Color(0xFF1E293B),
                                    ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),

                          if (_hideIdentifierField &&
                              (_savedIdentifier ?? '').trim().isNotEmpty) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withOpacity(0.08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color:
                                      const Color(0xFF6366F1).withOpacity(0.18),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.person_outline,
                                      color: Color(0xFF6366F1)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      _savedIdentifier!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1E293B),
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () async {
                                      final prefs =
                                          await SharedPreferences.getInstance();
                                      await prefs.remove(
                                          'last_login_identifier');
                                      if (!mounted) return;
                                      setState(() {
                                        _hideIdentifierField = false;
                                        _savedIdentifier = null;
                                        _emailController.clear();
                                      });
                                    },
                                    child: const Text('Өөр хүн'),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ] else ...[
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
                          ],

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
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
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
                          const SizedBox(height: 20),

                          // Server URL: production дээр нуусан.
                          // (Хадгалсан утга / анхдагч утга нь _applyLoginServerUrl() дээр үргэлж ашиглагдана.)
                          // Username "Намайг сана" идэвхтэй (identifier нуусан) үед Server URL огт харагдахгүй.
                          if (kDebugMode && !_hideIdentifierField) ...[
                            TextFormField(
                              controller: _serverUrlController,
                              keyboardType: TextInputType.url,
                              decoration: InputDecoration(
                                labelText: 'Server URL (debug)',
                                hintText: 'http://192.168.1.5:3000',
                                helperText:
                                    'Жишээ: LAN эсвэл порт 3000. Анхдагч: ${ApiConfig.defaultBackendServerUrl}',
                                helperMaxLines: 2,
                                prefixIcon: const Icon(Icons.dns_outlined),
                              ),
                              validator: (value) {
                                final v = value?.trim() ?? '';
                                if (v.isEmpty) return null;
                                final lower = v.toLowerCase();
                                if (!lower.startsWith('http://') &&
                                    !lower.startsWith('https://')) {
                                  return 'http:// эсвэл https:// ээр эхэлнэ үү';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Remember me + Biometric
                          Row(
                            children: [
                              Expanded(
                                child: SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text('Намайг сана'),
                                  value: _rememberMe,
                                  onChanged: (v) async {
                                    setState(() => _rememberMe = v);
                                    final prefs =
                                        await SharedPreferences.getInstance();
                                    await prefs.setBool('remember_me', v);
                                    if (!v) {
                                      await prefs.remove('last_login_identifier');
                                      setState(() {
                                        _hideIdentifierField = false;
                                        _savedIdentifier = null;
                                        _biometricEnabled = false;
                                      });
                                      await _saveBiometricEnabled(false);
                                    }
                                  },
                                ),
                              ),
                            ],
                          ),
                          if (_rememberMe && _biometricSupported) ...[
                            const SizedBox(height: 6),
                            SwitchListTile.adaptive(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Хурууны хээ ашиглах'),
                              value: _biometricEnabled,
                              onChanged: (v) async {
                                setState(() => _biometricEnabled = v);
                                await _saveBiometricEnabled(v);
                              },
                            ),
                          ],
                          if (_rememberMe &&
                              _biometricSupported &&
                              _biometricEnabled &&
                              _hasSavedToken) ...[
                            const SizedBox(height: 8),
                            Center(
                              child: Semantics(
                                button: true,
                                label: 'Хурууны хээгээр нэвтрэх',
                                child: InkWell(
                                  onTap:
                                      _isLoading ? null : _loginWithBiometrics,
                                  borderRadius: BorderRadius.circular(40),
                                  child: Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(0xFF6366F1)
                                          .withOpacity(0.10),
                                      border: Border.all(
                                        color: const Color(0xFF6366F1)
                                            .withOpacity(0.35),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.fingerprint_rounded,
                                      size: 34,
                                      color: Color(0xFF6366F1),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),

                          // Login Button
                          Consumer<MobileUserLoginProvider>(
                            builder: (context, loginProvider, _) {
                              final isBlocked = !loginProvider.canAttemptLogin;
                              final rateLimitUntil =
                                  loginProvider.rateLimitUntil;
                              String? waitMessage;

                              if (isBlocked && rateLimitUntil != null) {
                                final waitSeconds = rateLimitUntil
                                    .difference(DateTime.now())
                                    .inSeconds;
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
                                  onPressed:
                                      (_isLoading || isBlocked) ? null : _login,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6366F1),
                                    foregroundColor: Colors.white,
                                    elevation: 3,
                                    shadowColor: const Color(0xFF6366F1)
                                        .withOpacity(0.4),
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
