import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '/core/api_client.dart';
import '../app_routes.dart';

class SynCalAuthPage extends StatefulWidget {
  const SynCalAuthPage({super.key});

  @override
  State<SynCalAuthPage> createState() => _SynCalAuthPageState();
}

class _SynCalAuthPageState extends State<SynCalAuthPage>
    with TickerProviderStateMixin {
  bool _isRegisterMode = false;
  bool _isLoading = false;

  final _loginUsernameController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _regUsernameController = TextEditingController();
  final _regClassController = TextEditingController();
  final _regPasswordController = TextEditingController();
  final _regConfirmPasswordController = TextEditingController();

  bool _showLoginPassword = false;
  bool _showRegPassword = false;
  bool _showRegConfirmPassword = false;

  String _selectedGender = 'Male';
  String? _errorMessage;
  String? _successMessage;

  late final AnimationController _entranceController;

  static const Color bgDark = Color(0xFF1C1C1E);
  static const Color zinc900 = Color(0xFF18181B);
  static const Color zinc800 = Color(0xFF27272A);
  static const Color zinc600 = Color(0xFF52525B);
  static const Color zinc500 = Color(0xFF71717A);
  static const Color zinc400 = Color(0xFFA1A1AA);

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _loginUsernameController.dispose();
    _loginPasswordController.dispose();
    _regUsernameController.dispose();
    _regClassController.dispose();
    _regPasswordController.dispose();
    _regConfirmPasswordController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  Animation<double> _stagger(double start, double end) {
    return CurvedAnimation(
      parent: _entranceController,
      curve: Interval(start, end, curve: Curves.easeOutCubic),
    );
  }

  Widget _fadeSlideIn({
    required Animation<double> animation,
    required Widget child,
    double offset = 24,
  }) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        return Opacity(
          opacity: animation.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, offset * (1 - animation.value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  void _navigateToHome() {
    final settingsBox = Hive.box('settings');
    settingsBox.put('isLoggedIn', true);
    context.go(AppRoutes.home);
  }

  Future<void> _triggerLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final username = _loginUsernameController.text.trim();
      final password = _loginPasswordController.text.trim();
      if (username.isEmpty || password.isEmpty) {
        setState(() => _errorMessage = 'Please enter username and password');
        return;
      }
      await ApiClient.instance.login(username, password);
      if (mounted) {
        setState(() => _successMessage = 'Authentication successful! Redirecting...');
        await Future.delayed(const Duration(milliseconds: 500));
        _navigateToHome();
      }
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'Connection failed. Try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _triggerRegister() async {
    if (_regPasswordController.text != _regConfirmPasswordController.text) {
      setState(() {
        _errorMessage = 'Passwords do not match! Please verify workspace password.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      final username = _regUsernameController.text.trim();
      final password = _regPasswordController.text.trim();
      final className = _regClassController.text.trim();
      final gender = _selectedGender;
      if (username.isEmpty || password.isEmpty || className.isEmpty) {
        setState(() => _errorMessage = 'All fields are required');
        return;
      }
      await ApiClient.instance.register(
        username: username,
        password: password,
        gender: gender,
        className: className,
      );
      if (mounted) {
        setState(() => _successMessage = 'Workspace registered successfully! Redirecting...');
        await Future.delayed(const Duration(milliseconds: 500));
        _navigateToHome();
      }
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } catch (_) {
      setState(() => _errorMessage = 'Connection failed. Try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isMismatch = _regConfirmPasswordController.text.isNotEmpty &&
        (_regPasswordController.text != _regConfirmPasswordController.text);

    return Scaffold(
      backgroundColor: bgDark,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Soft ambient blur blobs matching the onboarding screen's
          // frosted, layered look, since there's no photo background here.
          Positioned(
            top: -80,
            left: -60,
            child: _fadeSlideIn(
              animation: _stagger(0.0, 0.6),
              offset: -20,
              child: _GlowBlob(
                color: Colors.white.withValues(alpha: 0.05),
                size: 260,
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -80,
            child: _fadeSlideIn(
              animation: _stagger(0.1, 0.7),
              offset: 20,
              child: _GlowBlob(
                color: Colors.white.withValues(alpha: 0.04),
                size: 320,
              ),
            ),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // ── Logo + welcome header, styled like the onboarding
                      // top scrim block (icon, title, subtitle).
                      _fadeSlideIn(
                        animation: _stagger(0.0, 0.5),
                        offset: -20,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Image.asset(
                                'assets/icons/syncal.png',
                                width: 72,
                                height: 72,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      color: zinc900,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: zinc800, width: 0.5),
                                    ),
                                    child: const Icon(
                                      Icons.sync_rounded,
                                      color: Colors.white70,
                                      size: 32,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              'Welcome to SynCal',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _isRegisterMode
                                  ? 'Setup a new user workspace core'
                                  : 'Sign in to active system terminal',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.55),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // ── Form now sits directly on the screen background —
                      // no card/frosted container behind the fields anymore.
                      _fadeSlideIn(
                        animation: _stagger(0.25, 0.85),
                        offset: 30,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_errorMessage != null) ...[
                              _buildStatusBanner(_errorMessage!, Colors.redAccent),
                              const SizedBox(height: 16),
                            ],
                            if (_successMessage != null) ...[
                              _buildStatusBanner(_successMessage!, Colors.green),
                              const SizedBox(height: 16),
                            ],

                            AnimatedSize(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeInOut,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 260),
                                transitionBuilder: (child, animation) {
                                  return FadeTransition(
                                    opacity: animation,
                                    child: SlideTransition(
                                      position: Tween<Offset>(
                                        begin: const Offset(0, 0.08),
                                        end: Offset.zero,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  );
                                },
                                child: _isRegisterMode
                                    ? _buildRegisterFormLayout(isMismatch)
                                    : _buildLoginFormLayout(),
                              ),
                            ),

                            const SizedBox(height: 20),
                            Center(
                              child: SizedBox(
                                width: double.infinity,
                                child: TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _isRegisterMode = !_isRegisterMode;
                                      _errorMessage = null;
                                      _successMessage = null;
                                    });
                                  },
                                  child: Text(
                                    _isRegisterMode
                                        ? 'Existing user terminal? Sign In'
                                        : 'New user? Setup Account Core',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: zinc400,
                                      decoration: TextDecoration.underline,
                                      decorationColor: zinc800,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 28),
                      _fadeSlideIn(
                        animation: _stagger(0.4, 0.9),
                        offset: 20,
                        child: const Text(
                          'POWERED BY CALBRS',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            letterSpacing: 2,
                            color: zinc600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginFormLayout() {
    return Column(
      key: const ValueKey('login'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildInputField(controller: _loginUsernameController, label: 'Username', hint: 'Enter terminal username'),
        const SizedBox(height: 16),
        _buildInputField(
          controller: _loginPasswordController,
          label: 'Password',
          hint: 'Enter workspace key',
          isPassword: true,
          obscureText: !_showLoginPassword,
          onToggleVisibility: () => setState(() => _showLoginPassword = !_showLoginPassword),
        ),
        const SizedBox(height: 24),
        _buildSubmitButton(label: _isLoading ? 'Authenticating Terminal...' : 'Sign In', onPressed: _triggerLogin),
      ],
    );
  }

  Widget _buildRegisterFormLayout(bool isMismatch) {
    return Column(
      key: const ValueKey('register'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildInputField(controller: _regUsernameController, label: 'System Username', hint: 'e.g., user_juma'),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: zinc800, width: 0.5),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedGender,
                    dropdownColor: bgDark,
                    icon: const Icon(Icons.arrow_drop_down, color: zinc500),
                    style: const TextStyle(fontSize: 12, color: zinc400, fontWeight: FontWeight.w500),
                    onChanged: (String? value) {
                      if (value != null) setState(() => _selectedGender = value);
                    },
                    items: <String>['Male', 'Female'].map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(value: value, child: Text(value));
                    }).toList(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildInputField(controller: _regClassController, label: 'Group', hint: 'Class matrix'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildInputField(
          controller: _regPasswordController,
          label: 'Workspace Password',
          hint: 'Create deep secure phrase',
          isPassword: true,
          obscureText: !_showRegPassword,
          onToggleVisibility: () => setState(() => _showRegPassword = !_showRegPassword),
        ),
        const SizedBox(height: 16),
        _buildInputField(
          controller: _regConfirmPasswordController,
          label: 'Confirm Password',
          hint: 'Verify secure phrase',
          isPassword: true,
          obscureText: !_showRegConfirmPassword,
          onToggleVisibility: () => setState(() => _showRegConfirmPassword = !_showRegConfirmPassword),
          isErrorBorder: isMismatch,
          onChanged: (val) => setState(() {}),
        ),
        if (isMismatch) ...[
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 8),
            child: Text('✕ Passwords do not match yet.', style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w500)),
          ),
        ],
        const SizedBox(height: 24),
        _buildSubmitButton(label: _isLoading ? 'Deploying Workspace Registry...' : 'Register Account', onPressed: _triggerRegister),
      ],
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    bool isPassword = false,
    bool obscureText = false,
    VoidCallback? onToggleVisibility,
    bool isErrorBorder = false,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(color: zinc600, fontSize: 12),
        labelStyle: const TextStyle(color: zinc500, fontSize: 12),
        floatingLabelStyle: const TextStyle(color: zinc400, fontSize: 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        filled: false,
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(
                  obscureText ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: zinc500,
                  size: 18,
                ),
                onPressed: onToggleVisibility,
              )
            : null,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(100),
          borderSide: BorderSide(color: isErrorBorder ? Colors.redAccent.withValues(alpha: 0.6) : zinc800, width: 0.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(100),
          borderSide: BorderSide(color: isErrorBorder ? Colors.redAccent : zinc600, width: 0.5),
        ),
      ),
    );
  }

  Widget _buildSubmitButton({required String label, required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.5),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            label,
            key: ValueKey(label),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBanner(String text, Color baseColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: baseColor.withValues(alpha: 0.2), width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: baseColor.withValues(alpha: 0.9)),
        textAlign: TextAlign.center,
      ),
    );
  }
}

/// Soft blurred glow circle used as ambient background decoration, echoing
/// the frosted, layered visual language of the onboarding screen's scrims.
class _GlowBlob extends StatelessWidget {
  final Color color;
  final double size;

  const _GlowBlob({required this.color, required this.size});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}