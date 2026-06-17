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

class _SynCalAuthPageState extends State<SynCalAuthPage> {
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

  static const Color zinc950 = Color(0xFF09090B);
  static const Color zinc900 = Color(0xFF18181B);
  static const Color zinc800 = Color(0xFF27272A);
  static const Color zinc600 = Color(0xFF52525B);
  static const Color zinc500 = Color(0xFF71717A);
  static const Color zinc400 = Color(0xFFA1A1AA);
  static const Color zinc300 = Color(0xFFD4D4D8);

  @override
  void dispose() {
    _loginUsernameController.dispose();
    _loginPasswordController.dispose();
    _regUsernameController.dispose();
    _regClassController.dispose();
    _regPasswordController.dispose();
    _regConfirmPasswordController.dispose();
    super.dispose();
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
      backgroundColor: zinc950,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('SynCal', style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: -1)),
                const SizedBox(height: 4),
                Text(
                  _isRegisterMode ? 'Setup a new user workspace core' : 'Sign in to active system terminal',
                  style: const TextStyle(fontSize: 12, color: zinc500, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 32),

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
                  child: _isRegisterMode ? _buildRegisterFormLayout(isMismatch) : _buildLoginFormLayout(),
                ),

                const SizedBox(height: 24),
                Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() {
                        _isRegisterMode = !_isRegisterMode;
                        _errorMessage = null;
                        _successMessage = null;
                      });
                    },
                    child: Text(
                      _isRegisterMode ? 'Existing user terminal? Sign In' : 'New user? Setup Account Core',
                      style: const TextStyle(fontSize: 11, color: zinc400, decoration: TextDecoration.underline, decorationColor: zinc800),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
                const Center(
                  child: Text('POWERED BY CALBRS', style: TextStyle(fontFamily: 'monospace', fontSize: 10, letterSpacing: 2, color: zinc600)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoginFormLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
      crossAxisAlignment: CrossAxisAlignment.start,
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
                    dropdownColor: zinc950,
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
        filled: true,
        fillColor: Colors.transparent,
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
      child: ElevatedButton(
        onPressed: _isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: zinc950,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.5),
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
        ),
        child: Text(label.toUpperCase(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
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