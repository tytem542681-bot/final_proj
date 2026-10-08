import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'firebase_service.dart';
import 'local_store.dart';
import 'maintenance_report.dart';

void main() {
  runApp(const FixTrackApp());
}

const _ink = Color(0xFF0F1E38);
const _muted = Color(0xFF64748B);
const _canvas = Color(0xFFF8FAFC);
const _green = Color(0xFFF59E0B);
const _line = Color(0xFFE2E8F0);
const _deepBlue = Color(0xFF0A1628);
const _panelBlue = Color(0xFF1A2F52);

void _noop() {}

class FixTrackApp extends StatefulWidget {
  const FixTrackApp({super.key});

  @override
  State<FixTrackApp> createState() => _FixTrackAppState();
}

class _FixTrackAppState extends State<FixTrackApp> {
  late Future<LocalStore> _storeFuture;

  @override
  void initState() {
    super.initState();
    _storeFuture = _loadStore();
  }

  void _retryLoad() {
    setState(() => _storeFuture = _loadStore());
  }

  Future<LocalStore> _loadStore() async {
    await FirebaseService.initializeIfConfigured();
    return LocalStore.load();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _green,
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'FixTrack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: _canvas,
        appBarTheme: const AppBarTheme(
          backgroundColor: _deepBlue,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: _line),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF8F9FA),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _green, width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _green,
            foregroundColor: Colors.white,
            minimumSize: const Size(48, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            textStyle: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        chipTheme: ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30),
            side: BorderSide.none,
          ),
          labelStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 3),
        ),
      ),
      home: FutureBuilder<LocalStore>(
        future: _storeFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return StartupError(error: snapshot.error, onRetry: _retryLoad);
          }
          if (!snapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator(color: _green)),
            );
          }
          return LoginGate(store: snapshot.data!);
        },
      ),
    );
  }
}

class StartupError extends StatelessWidget {
  const StartupError({required this.error, required this.onRetry, super.key});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48, color: _muted),
            const SizedBox(height: 16),
            const Text(
              'FixTrack could not load',
              style: TextStyle(
                color: _ink,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text('$error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    ),
  );
}

class LoginGate extends StatefulWidget {
  const LoginGate({required this.store, super.key});

  final LocalStore store;

  @override
  State<LoginGate> createState() => _LoginGateState();
}

class _LoginGateState extends State<LoginGate> {
  bool _signedIn = false;

  Future<void> _logout() async {
    if (FirebaseService.isReady) {
      await FirebaseService.auth.signOut();
      await widget.store.disconnectFirebaseAccount();
    }
    if (!mounted) return;
    setState(() => _signedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_signedIn) {
      return MainShell(store: widget.store, onLogout: _logout);
    }
    return LoginPage(
      onLogin: (role, displayName, email, password) async {
        if (FirebaseService.isReady) {
          final account = await FirebaseService.signIn(
            email: email,
            password: password,
            requestedRole: role.name,
          );
          try {
            await widget.store.connectFirebaseAccount(account);
          } catch (_) {
            await FirebaseService.auth.signOut();
            await widget.store.disconnectFirebaseAccount();
            rethrow;
          }
        } else {
          await widget.store.updateProfile(
            displayName: displayName,
            email: email,
            role: role,
          );
        }
        if (mounted) setState(() => _signedIn = true);
      },
      onRegister: (role, displayName, email, password) async {
        if (!FirebaseService.isReady) {
          throw StateError(FirebaseService.setupMessage);
        }
        final account = await FirebaseService.register(
          displayName: displayName,
          email: email,
          password: password,
          requestedRole: role.name,
        );
        if (role == UserRole.campusUser) {
          await widget.store.connectFirebaseAccount(account);
          if (mounted) setState(() => _signedIn = true);
          return true;
        }
        return false;
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({required this.onLogin, required this.onRegister, super.key});

  final Future<void> Function(
    UserRole role,
    String displayName,
    String email,
    String password,
  )
  onLogin;
  final Future<bool> Function(
    UserRole role,
    String displayName,
    String email,
    String password,
  )
  onRegister;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  UserRole _tab = UserRole.campusUser;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _error;
  bool _submitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = _tab == UserRole.admin;
    final isMaintenance = _tab == UserRole.maintenance;
    final client = _tab == UserRole.campusUser;
    return Scaffold(
      backgroundColor: _deepBlue,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: _green,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40F59E0B),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.home_repair_service_rounded,
                  size: 34,
                  color: Color(0xFF0A1628),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'FIXTRACK',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.12,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'CAMPUS FACILITY MAINTENANCE',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 10,
                  letterSpacing: 0.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 26),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: _panelBlue,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2A4A72)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _LoginTab(
                        label: 'Campus',
                        selected: client,
                        onTap: () => setState(() => _tab = UserRole.campusUser),
                      ),
                    ),
                    Expanded(
                      child: _LoginTab(
                        label: 'Maintenance',
                        selected: isMaintenance,
                        onTap: () =>
                            setState(() => _tab = UserRole.maintenance),
                      ),
                    ),
                    Expanded(
                      child: _LoginTab(
                        label: 'Admin',
                        selected: isAdmin,
                        onTap: () => setState(() => _tab = UserRole.admin),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _panelBlue,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isAdmin
                        ? const Color(0x40F59E0B)
                        : const Color(0xFF2A4A72),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: isAdmin ? _green : const Color(0xFF10B981),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isAdmin
                                ? 'Campus administrators — review, prioritize, and assign all tickets'
                                : isMaintenance
                                ? 'Maintenance personnel — view assigned tasks and update progress'
                                : 'Students, faculty, and staff — report and track facility issues',
                            style: const TextStyle(
                              color: Color(0xFF94A3B8),
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      isAdmin
                          ? 'ADMIN EMAIL'
                          : isMaintenance
                          ? 'MAINTENANCE EMAIL'
                          : 'EMAIL ADDRESS',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.06,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: isAdmin || isMaintenance
                            ? 'staff@campus.edu'
                            : 'you@campus.edu',
                        hintStyle: const TextStyle(color: Color(0xFF64748B)),
                        filled: true,
                        fillColor: const Color(0xFF1A2F52),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF2A4A72),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF2A4A72),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: _green,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'PASSWORD',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.06,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: '••••••••',
                        hintStyle: const TextStyle(color: Color(0xFF64748B)),
                        filled: true,
                        fillColor: const Color(0xFF1A2F52),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF2A4A72),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF2A4A72),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: _green,
                            width: 1.5,
                          ),
                        ),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF450A0A),
                          border: Border.all(color: const Color(0xFFEF4444)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFFCA5A5),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _submitting ? null : _handleLogin,
                        style: FilledButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: const Color(0xFF0A1628),
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          _submitting ? 'Signing in…' : 'Sign in',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _submitting
                            ? null
                            : () => Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) => RegisterPage(
                                    onRegister: widget.onRegister,
                                  ),
                                ),
                              ),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Register'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          side: const BorderSide(color: Color(0xFF54749D)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2F52),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF2A4A72)),
                ),
                child: Text(
                  FirebaseService.isReady
                      ? 'Sign in with an account enabled in Firebase Authentication.'
                      : FirebaseService.setupMessage,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleLogin() async {
    setState(() {
      _error = null;
    });

    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please enter your email and password.');
      return;
    }
    if (!FirebaseService.isValidEmail(email)) {
      setState(
        () => _error = 'Enter a valid email address, such as name@example.com.',
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      await widget.onLogin(
        _tab,
        FirebaseService.isReady
            ? email.split('@').first
            : _tab == UserRole.admin
            ? 'Campus Administrator'
            : _tab == UserRole.maintenance
            ? 'Maintenance Staff'
            : 'Alex Morgan',
        email,
        password,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _error = FirebaseService.signInErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class RegisterPage extends StatefulWidget {
  const RegisterPage({required this.onRegister, super.key});

  final Future<bool> Function(
    UserRole role,
    String displayName,
    String email,
    String password,
  )
  onRegister;

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  UserRole _role = UserRole.campusUser;
  bool _submitting = false;
  bool _created = false;
  bool _autoSignedIn = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _deepBlue,
    appBar: AppBar(
      backgroundColor: _deepBlue,
      title: const Text('Create account'),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
        children: [
          Text(
            _created ? 'Account created' : 'Join FixTrack',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _created
                ? _autoSignedIn
                      ? 'Your campus user account is ready.'
                      : 'Your maintenance staff access request was sent. An administrator must approve it before you can access assigned tasks.'
                : 'Create an account with Firebase Authentication.',
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          if (!_created) ...[
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _panelBlue,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF2A4A72)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'ACCOUNT TYPE',
                    style: TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.06,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<UserRole>(
                    segments: const [
                      ButtonSegment(
                        value: UserRole.campusUser,
                        label: Text('Campus user'),
                      ),
                      ButtonSegment(
                        value: UserRole.maintenance,
                        label: Text('Request maintenance'),
                      ),
                    ],
                    selected: {_role},
                    onSelectionChanged: (selection) =>
                        setState(() => _role = selection.first),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    _role == UserRole.maintenance
                        ? 'Maintenance access requires administrator approval. Admin access is assigned separately and cannot be requested here.'
                        : 'Campus accounts can sign in immediately after registration.',
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _registerLabel('DISPLAY NAME'),
                  TextField(
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _registerDecoration('Your name'),
                  ),
                  const SizedBox(height: 14),
                  _registerLabel('EMAIL ADDRESS'),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: _registerDecoration('you@campus.edu'),
                  ),
                  const SizedBox(height: 14),
                  _registerLabel('PASSWORD'),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: _registerDecoration(
                      'At least 6 characters',
                      suffixIcon: IconButton(
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _registerLabel('CONFIRM PASSWORD'),
                  TextField(
                    controller: _confirmPasswordController,
                    obscureText: _obscurePassword,
                    decoration: _registerDecoration('Re-enter your password'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF450A0A),
                        border: Border.all(color: const Color(0xFFEF4444)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: Color(0xFFFCA5A5),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _submitting ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: const Color(0xFF0A1628),
                        minimumSize: const Size.fromHeight(52),
                      ),
                      child: Text(
                        _submitting
                            ? 'Creating account…'
                            : _role == UserRole.maintenance
                            ? 'Create account & request maintenance'
                            : 'Create account',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                _autoSignedIn ? 'Continue to FixTrack' : 'Back to sign in',
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _registerLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        color: Color(0xFF94A3B8),
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.06,
      ),
    ),
  );

  InputDecoration _registerDecoration(String hint, {Widget? suffixIcon}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF64748B)),
        filled: true,
        fillColor: const Color(0xFF1A2F52),
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2A4A72)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF2A4A72)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _green, width: 1.5),
        ),
      );

  Future<void> _submit() async {
    setState(() => _error = null);
    final name = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    if (name.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Complete all fields to continue.');
      return;
    }
    if (!FirebaseService.isValidEmail(email)) {
      setState(
        () => _error = 'Enter a valid email address, such as name@example.com.',
      );
      return;
    }
    if (password.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (password != _confirmPasswordController.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }

    setState(() => _submitting = true);
    try {
      final autoSignedIn = await widget.onRegister(
        _role,
        name,
        email,
        password,
      );
      if (!mounted) return;
      setState(() {
        _created = true;
        _autoSignedIn = autoSignedIn;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _error = FirebaseService.signInErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class _LoginTab extends StatelessWidget {
  const _LoginTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(9),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? _green : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Center(
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: selected ? const Color(0xFF0A1628) : const Color(0xFF64748B),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.08,
          ),
        ),
      ),
    ),
  );
}

class MainShell extends StatefulWidget {
  const MainShell({required this.store, this.onLogout = _noop, super.key});

  final LocalStore store;
  final VoidCallback onLogout;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final destinations = <NavigationDestination>[
          const NavigationDestination(
            icon: Icon(Icons.grid_view_rounded),
            label: 'Home',
          ),
          const NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            label: 'My reports',
          ),
          if (widget.store.isMaintenance)
            const NavigationDestination(
              icon: Icon(Icons.handyman_outlined),
              label: 'Manage',
            ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            label: 'Profile',
          ),
        ];
        if (_selectedIndex >= destinations.length) _selectedIndex = 0;
        final pages = <Widget>[
          HomePage(
            store: widget.store,
            onNewReport: _openReportForm,
            onNotifications: _openNotifications,
          ),
          ReportListPage(
            store: widget.store,
            onBackToHome: () => setState(() => _selectedIndex = 0),
          ),
          if (widget.store.isMaintenance) MaintenancePage(store: widget.store),
          ProfilePage(store: widget.store, onLogout: widget.onLogout),
        ];

        return Scaffold(
          appBar: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: SafeArea(
              child: Container(
                color: _deepBlue,
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
                child: Row(
                  children: [
                    const Expanded(child: BrandMark()),
                    const LocalModeBadge(),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Notifications',
                      onPressed: _openNotifications,
                      icon: NotificationBell(store: widget.store),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Log out',
                      onPressed: widget.onLogout,
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          body: IndexedStack(index: _selectedIndex, children: pages),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) =>
                setState(() => _selectedIndex = index),
            destinations: destinations,
          ),
        );
      },
    );
  }

  Future<void> _openReportForm() async {
    final created = await Navigator.of(context).push<MaintenanceReport>(
      MaterialPageRoute(builder: (_) => ReportFormPage(store: widget.store)),
    );
    if (!mounted || created == null) return;
    setState(() => _selectedIndex = 1);
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ReportDetailsPage(store: widget.store, reportId: created.id),
      ),
    );
  }

  void _openNotifications() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => NotificationsPage(store: widget.store)),
    );
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: _green,
          borderRadius: BorderRadius.circular(11),
          boxShadow: const [
            BoxShadow(
              color: Color(0x40F59E0B),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(
          Icons.home_repair_service_rounded,
          size: 19,
          color: Color(0xFF0A1628),
        ),
      ),
      const SizedBox(width: 10),
      const Text(
        'FixTrack',
        style: TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
        ),
      ),
    ],
  );
}

class LocalModeBadge extends StatelessWidget {
  const LocalModeBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final cloudConnected = FirebaseService.isReady;
    final foreground = cloudConnected
        ? const Color(0xFF146C43)
        : const Color(0xFF845A17);
    return Tooltip(
      message: cloudConnected
          ? 'Signed in with Firebase Authentication; reports sync with Cloud Firestore.'
          : 'Local demo: data is stored on this device.',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: cloudConnected
              ? const Color(0xFFE4F4EB)
              : const Color(0xFFFFF2D8),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              cloudConnected
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              size: 13,
              color: foreground,
            ),
            const SizedBox(width: 4),
            Text(
              cloudConnected ? 'FIREBASE' : 'LOCAL DEMO',
              style: TextStyle(
                color: foreground,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationBell extends StatelessWidget {
  const NotificationBell({required this.store, super.key});

  final LocalStore store;

  @override
  Widget build(BuildContext context) {
    final count = store.unreadNotificationCount;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(
          Icons.notifications_none_rounded,
          size: 25,
          color: Colors.white,
        ),
        if (count > 0)
          Positioned(
            right: -3,
            top: -3,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: const BoxDecoration(
                color: Color(0xFFDF5E56),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  count > 9 ? '9+' : '$count',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    required this.store,
    required this.onNewReport,
    required this.onNotifications,
    super.key,
  });

  final LocalStore store;
  final VoidCallback onNewReport;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) {
    final reports = store.myReports;
    final activeCount = reports
        .where(
          (report) =>
              report.status != ReportStatus.resolved &&
              report.status != ReportStatus.rejected,
        )
        .length;
    final resolvedCount = reports
        .where((report) => report.status == ReportStatus.resolved)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Container(
          margin: const EdgeInsets.only(top: 0, bottom: 18),
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: const BoxDecoration(
            color: _deepBlue,
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(24),
              bottomRight: Radius.circular(24),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 6),
              const Text(
                'WELCOME BACK',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  letterSpacing: 0.12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                store.displayName,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'CAMPUS USER',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  letterSpacing: 0.08,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _MetricCard(
                      label: 'ACTIVE TICKETS',
                      count: activeCount,
                      icon: Icons.pending_actions_rounded,
                      tint: const Color(0xFF1A2F52),
                      iconColor: _green,
                      valueColor: _green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _MetricCard(
                      label: 'RESOLVED',
                      count: resolvedCount,
                      icon: Icons.check_circle_outline_rounded,
                      tint: const Color(0xFF1A2F52),
                      iconColor: const Color(0xFF10B981),
                      valueColor: const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _ReportActionCard(onTap: onNewReport),
        const SizedBox(height: 20),
        SectionHeading(
          title: 'Recent reports',
          actionLabel: 'VIEW ALL →',
          onAction: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => ReportListPage(store: store)),
          ),
        ),
        const SizedBox(height: 8),
        if (reports.isEmpty)
          const EmptyState(
            icon: Icons.assignment_outlined,
            title: 'No reports yet',
            message: 'Your submitted maintenance reports will show up here.',
          )
        else
          ...reports
              .take(3)
              .map(
                (report) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ReportCard(
                    report: report,
                    onTap: () => _openDetails(context, store, report),
                  ),
                ),
              ),
        const SizedBox(height: 18),
        _SupportCard(onTap: onNotifications),
      ],
    );
  }

  static void _openDetails(
    BuildContext context,
    LocalStore store,
    MaintenanceReport report,
  ) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ReportDetailsPage(store: store, reportId: report.id),
      ),
    );
  }
}

class _ReportActionCard extends StatelessWidget {
  const _ReportActionCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF0F1E38), Color(0xFF1A2F52)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFF2A4A72)),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Spotted something?',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tell us what needs fixing.',
                style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const Key('new-report-button'),
                onPressed: onTap,
                icon: const Icon(Icons.add_rounded, size: 19),
                label: const Text('Report new issue'),
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: const Color(0xFF0A1628),
                  minimumSize: const Size(0, 43),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const Icon(
          Icons.build_circle_outlined,
          color: Color(0x88F59E0B),
          size: 76,
        ),
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.count,
    required this.icon,
    required this.tint,
    required this.iconColor,
    this.valueColor,
  });

  final String label;
  final int count;
  final IconData icon;
  final Color tint;
  final Color iconColor;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: tint,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFF2A4A72)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontSize: 10,
            letterSpacing: 0.08,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: iconColor.withAlpha(40),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const Spacer(),
            Text(
              '$count',
              style: TextStyle(
                color: valueColor ?? Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading({
    required this.title,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      if (actionLabel != null)
        TextButton(
          onPressed: onAction,
          child: Text(
            actionLabel!,
            style: const TextStyle(
              color: Color(0xFF3A5F8A),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ),
    ],
  );
}

class _SupportCard extends StatelessWidget {
  const _SupportCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Ink(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1F7),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(Icons.notifications_active_outlined, color: _green),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stay in the loop',
                  style: TextStyle(color: _ink, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 2),
                Text(
                  'View the latest report updates',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: _muted),
        ],
      ),
    ),
  );
}

class ReportListPage extends StatefulWidget {
  const ReportListPage({required this.store, this.onBackToHome, super.key});

  final LocalStore store;
  final VoidCallback? onBackToHome;

  @override
  State<ReportListPage> createState() => _ReportListPageState();
}

class _ReportListPageState extends State<ReportListPage> {
  String _filter = 'All';
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final allReports = widget.store.myReports;
    final reports = allReports.where((report) {
      final matchesFilter = switch (_filter) {
        'Active' =>
          report.status != ReportStatus.resolved &&
              report.status != ReportStatus.rejected,
        'Resolved' => report.status == ReportStatus.resolved,
        _ => true,
      };
      final normalizedQuery = _query.toLowerCase().trim();
      final matchesQuery =
          normalizedQuery.isEmpty ||
          report.title.toLowerCase().contains(normalizedQuery) ||
          report.id.toLowerCase().contains(normalizedQuery) ||
          report.location.toLowerCase().contains(normalizedQuery);
      return matchesFilter && matchesQuery;
    }).toList();

    return Scaffold(
      backgroundColor: _canvas,
      body: Material(
        color: _canvas,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Back to home',
                  onPressed: () {
                    final navigator = Navigator.of(context);
                    if (navigator.canPop()) {
                      navigator.pop();
                    } else {
                      widget.onBackToHome?.call();
                    }
                  },
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(width: 4),
                const Expanded(
                  child: Text(
                    'My reports',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${allReports.length} maintenance ${allReports.length == 1 ? 'request' : 'requests'}',
              style: const TextStyle(color: _muted, fontSize: 13),
            ),
            const SizedBox(height: 16),
            TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                hintText: 'Search reports or locations',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 13),
            Wrap(
              spacing: 8,
              children: ['All', 'Active', 'Resolved'].map((filter) {
                final selected = filter == _filter;
                return ChoiceChip(
                  label: Text(filter),
                  selected: selected,
                  onSelected: (_) => setState(() => _filter = filter),
                  selectedColor: const Color(0xFFD8EEE6),
                  labelStyle: TextStyle(
                    color: selected ? _green : _muted,
                    fontWeight: FontWeight.w700,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            if (reports.isEmpty)
              EmptyState(
                icon: Icons.search_off_rounded,
                title: allReports.isEmpty
                    ? 'No reports yet'
                    : 'No matches found',
                message: allReports.isEmpty
                    ? 'Use “Report new issue” to submit your first request.'
                    : 'Try another search term or status filter.',
              )
            else
              ...reports.map(
                (report) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: ReportCard(
                    report: report,
                    onTap: () => _openDetails(context, report),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openDetails(BuildContext context, MaintenanceReport report) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ReportDetailsPage(store: widget.store, reportId: report.id),
      ),
    );
  }
}

class ReportCard extends StatelessWidget {
  const ReportCard({required this.report, required this.onTap, super.key});

  final MaintenanceReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CategoryIcon(category: report.category),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    report.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    report.location,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      StatusPill(status: report.status),
                      const SizedBox(width: 7),
                      Text(
                        report.id,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 5),
            Text(
              _shortDate(context, report.createdAt),
              style: const TextStyle(color: _muted, fontSize: 10),
            ),
          ],
        ),
      ),
    ),
  );
}

class CategoryIcon extends StatelessWidget {
  const CategoryIcon({required this.category, super.key});

  final String category;

  @override
  Widget build(BuildContext context) {
    final (icon, background, foreground) = switch (category) {
      'Electrical' => (
        Icons.bolt_rounded,
        const Color(0xFFFFF2D8),
        const Color(0xFFAE781E),
      ),
      'Plumbing' => (
        Icons.water_drop_outlined,
        const Color(0xFFE6F1FC),
        const Color(0xFF4775AF),
      ),
      'Furniture' => (
        Icons.chair_alt_outlined,
        const Color(0xFFF0E9FC),
        const Color(0xFF7B58A9),
      ),
      'Cleaning' => (
        Icons.cleaning_services_outlined,
        const Color(0xFFE8F5EC),
        const Color(0xFF4F9460),
      ),
      _ => (
        Icons.home_repair_service_outlined,
        const Color(0xFFEAF0F2),
        const Color(0xFF55727A),
      ),
    };
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: foreground, size: 21),
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({required this.status, super.key});

  final ReportStatus status;

  @override
  Widget build(BuildContext context) {
    final (background, foreground, dot) = switch (status) {
      ReportStatus.pending => (
        const Color(0xFFFFF3DA),
        const Color(0xFF946219),
        const Color(0xFFE3A735),
      ),
      ReportStatus.underReview => (
        const Color(0xFFEAF0FC),
        const Color(0xFF4C67A2),
        const Color(0xFF6C8CCB),
      ),
      ReportStatus.inProgress => (
        const Color(0xFFE7F1FC),
        const Color(0xFF3C719F),
        const Color(0xFF4A8ABF),
      ),
      ReportStatus.resolved => (
        const Color(0xFFE4F4EB),
        const Color(0xFF3F8055),
        const Color(0xFF4DAB6A),
      ),
      ReportStatus.rejected => (
        const Color(0xFFFCE9E7),
        const Color(0xFF9D4E48),
        const Color(0xFFD66B60),
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              color: foreground,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class MaintenancePage extends StatelessWidget {
  const MaintenancePage({required this.store, super.key});

  final LocalStore store;

  @override
  Widget build(BuildContext context) {
    final reports = store.workReports;
    final pending = reports
        .where(
          (report) =>
              report.status == ReportStatus.pending ||
              report.status == ReportStatus.underReview,
        )
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: [
        Text(
          store.isAdmin
              ? 'Administrator dashboard'
              : 'Assigned maintenance tasks',
          style: TextStyle(
            color: _ink,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          store.isAdmin
              ? 'Prioritize requests, assign staff, and monitor campus work.'
              : 'Review your assigned reports and update progress.',
          style: TextStyle(color: _muted, fontSize: 13),
        ),
        if (store.firebaseSyncError != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF450A0A),
              border: Border.all(color: const Color(0xFFEF4444)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              store.firebaseSyncError!,
              style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: 17),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F1F0),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(Icons.assignment_late_outlined, color: _green),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$pending ${pending == 1 ? 'report needs' : 'reports need'} review',
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${reports.length} total',
                style: const TextStyle(
                  color: _green,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
        if (store.isAdmin &&
            FirebaseService.isReady &&
            FirebaseService.auth.currentUser != null) ...[
          const SizedBox(height: 20),
          _MaintenanceAccessRequests(store: store),
        ],
        const SizedBox(height: 20),
        SectionHeading(
          title: store.isAdmin ? 'All campus reports' : 'Assigned to me',
        ),
        const SizedBox(height: 8),
        if (reports.isEmpty)
          EmptyState(
            icon: Icons.task_alt_rounded,
            title: store.isAdmin ? 'Queue is clear' : 'No tasks assigned',
            message: store.isAdmin
                ? 'New campus maintenance reports will appear here.'
                : 'Reports assigned to your maintenance account will appear here.',
          )
        else
          ...reports.map(
            (report) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ReportCard(
                report: report,
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) =>
                        ReportDetailsPage(store: store, reportId: report.id),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MaintenanceAccessRequests extends StatefulWidget {
  const _MaintenanceAccessRequests({required this.store});

  final LocalStore store;

  @override
  State<_MaintenanceAccessRequests> createState() =>
      _MaintenanceAccessRequestsState();
}

class _MaintenanceAccessRequestsState
    extends State<_MaintenanceAccessRequests> {
  late Future<List<FirebaseAccount>> _requests;
  final Set<String> _approving = {};

  @override
  void initState() {
    super.initState();
    _requests = widget.store.pendingMaintenanceRequests();
  }

  Future<void> _approve(FirebaseAccount request) async {
    setState(() => _approving.add(request.uid));
    try {
      await widget.store.approveMaintenanceRequest(request.uid);
      if (!mounted) return;
      setState(() => _requests = widget.store.pendingMaintenanceRequests());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${request.displayName} approved for maintenance.'),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not approve this request: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _approving.remove(request.uid));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<FirebaseAccount>>(
    future: _requests,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'Could not load staff access requests: ${snapshot.error}',
            ),
          ),
        );
      }
      final requests = snapshot.data ?? const <FirebaseAccount>[];
      if (snapshot.connectionState == ConnectionState.waiting &&
          requests.isEmpty) {
        return const Center(child: CircularProgressIndicator());
      }
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                title: 'Maintenance access requests (${requests.length})',
              ),
              if (requests.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: Text(
                    'No pending staff requests.',
                    style: TextStyle(color: _muted, fontSize: 13),
                  ),
                )
              else
                ...requests.map(
                  (request) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(request.displayName),
                    subtitle: Text(request.email),
                    trailing: TextButton(
                      onPressed: _approving.contains(request.uid)
                          ? null
                          : () => _approve(request),
                      child: Text(
                        _approving.contains(request.uid)
                            ? 'Approving…'
                            : 'Approve',
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class ReportFormPage extends StatefulWidget {
  const ReportFormPage({required this.store, super.key});

  final LocalStore store;

  @override
  State<ReportFormPage> createState() => _ReportFormPageState();
}

class _ReportFormPageState extends State<ReportFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _roomController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _category;
  String? _building;
  ReportPriority _priority = ReportPriority.medium;
  String? _photoPath;
  Uint8List? _selectedPhotoBytes;
  String? _selectedPhotoContentType;
  bool _submitting = false;
  final _picker = ImagePicker();
  static const _maxPhotoBytes = 3 * 1024 * 1024;

  static const _categories = [
    'Electrical',
    'Plumbing',
    'Furniture',
    'Cleaning',
    'Doors & Windows',
    'Safety',
    'Other',
  ];
  static const _buildings = [
    'CCE Building',
    'Main Building',
    'Library',
    'Science Building',
    'Gymnasium',
    'Other',
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _roomController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: _deepBlue,
      foregroundColor: Colors.white,
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NEW TICKET',
            style: TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.12,
            ),
          ),
          SizedBox(height: 2),
          Text(
            'Report Maintenance Issue',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).pop(),
      ),
    ),
    body: Form(
      key: _formKey,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Tell us what needs attention',
                style: TextStyle(
                  color: _ink,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                'Add a few details so our team can get right to it.',
                style: TextStyle(color: _muted, fontSize: 13),
              ),
              const SizedBox(height: 22),
              const _FormLabel('Issue title'),
              TextFormField(
                key: const Key('report-title-field'),
                controller: _titleController,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 80,
                decoration: const InputDecoration(
                  hintText: 'e.g. Leaking faucet in restroom',
                  counterText: '',
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 16),
              const _FormLabel('Problem category'),
              DropdownButtonFormField<String>(
                key: const Key('report-category-field'),
                initialValue: _category,
                decoration: const InputDecoration(
                  hintText: 'Choose a category',
                  prefixIcon: Icon(Icons.category_outlined),
                ),
                items: _categories
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _category = value),
                validator: (value) =>
                    value == null ? 'Choose a problem category.' : null,
              ),
              const SizedBox(height: 16),
              const _FormLabel('Where is the issue?'),
              DropdownButtonFormField<String>(
                key: const Key('report-building-field'),
                initialValue: _building,
                decoration: const InputDecoration(
                  hintText: 'Select a building',
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                items: _buildings
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _building = value),
                validator: (value) =>
                    value == null ? 'Select the building or facility.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _roomController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  hintText: 'Room, floor, or nearby landmark',
                  prefixIcon: Icon(Icons.meeting_room_outlined),
                ),
              ),
              const SizedBox(height: 16),
              const _FormLabel('Priority'),
              DropdownButtonFormField<ReportPriority>(
                initialValue: _priority,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                items: ReportPriority.values
                    .map(
                      (priority) => DropdownMenuItem(
                        value: priority,
                        child: Text(priority.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _priority = value);
                },
              ),
              const SizedBox(height: 16),
              const _FormLabel('Description'),
              TextFormField(
                key: const Key('report-description-field'),
                controller: _descriptionController,
                minLines: 4,
                maxLines: 6,
                maxLength: 500,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Describe what happened and any safety concerns.',
                  alignLabelWithHint: true,
                ),
                validator: _requiredValidator,
              ),
              const SizedBox(height: 14),
              const _FormLabel('Photo evidence'),
              _photoPicker(),
              const SizedBox(height: 24),
              FilledButton.icon(
                key: const Key('submit-report-button'),
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(_submitting ? 'Submitting…' : 'Submit ticket'),
              ),
              const SizedBox(height: 10),
              const Text(
                'Photo evidence is saved on this device only and is not '
                'shared with maintenance.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _photoPicker() {
    if (_photoPath != null) {
      return Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 180,
              width: double.infinity,
              child: _imageForPath(_photoPath!, fit: BoxFit.cover),
            ),
          ),
          Positioned(
            right: 9,
            top: 9,
            child: IconButton.filled(
              tooltip: 'Remove photo',
              onPressed: () => setState(() {
                _photoPath = null;
                _selectedPhotoBytes = null;
                _selectedPhotoContentType = null;
              }),
              icon: const Icon(Icons.close_rounded),
            ),
          ),
        ],
      );
    }
    return OutlinedButton.icon(
      onPressed: _choosePhoto,
      icon: const Icon(Icons.add_a_photo_outlined),
      label: const Text('Add a photo'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        foregroundColor: _green,
        side: const BorderSide(color: _line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Future<void> _choosePhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
              if (!kIsWeb)
                ListTile(
                  leading: const Icon(Icons.photo_camera_outlined),
                  title: const Text('Take a photo'),
                  onTap: () => Navigator.pop(context, ImageSource.camera),
                ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    try {
      final image = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        imageQuality: 70,
      );
      if (image != null && mounted) {
        final bytes = await image.readAsBytes().timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException(
            'Reading the selected photo timed out. Please choose it again.',
          ),
        );
        if (bytes.lengthInBytes > _maxPhotoBytes) {
          throw const FormatException(
            'Choose a photo smaller than 3 MB so it can be saved on this device.',
          );
        }
        final contentType = image.mimeType ?? 'image/jpeg';
        setState(() {
          _photoPath = 'data:$contentType;base64,${base64Encode(bytes)}';
          _selectedPhotoBytes = bytes;
          _selectedPhotoContentType = contentType;
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the photo picker: $error')),
      );
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final report = await widget.store.createReport(
        ReportDraft(
          title: _titleController.text,
          category: _category!,
          building: _building!,
          room: _roomController.text,
          priority: _priority,
          description: _descriptionController.text,
          reporter: widget.store.email,
          photoPath: _photoPath,
          photoBytes: _selectedPhotoBytes,
          photoContentType: _selectedPhotoContentType,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop(report);
      }
    } catch (error) {
      if (!mounted) return;
      final message = error is TimeoutException
          ? error.message ?? 'The request timed out. Please try again.'
          : error;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the report: $message')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  static String? _requiredValidator(String? value) =>
      value == null || value.trim().isEmpty ? 'This field is required.' : null;
}

class _FormLabel extends StatelessWidget {
  const _FormLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: Color(0xFF374151),
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.06,
      ),
    ),
  );
}

class ReportDetailsPage extends StatefulWidget {
  const ReportDetailsPage({
    required this.store,
    required this.reportId,
    super.key,
  });

  final LocalStore store;
  final String reportId;

  @override
  State<ReportDetailsPage> createState() => _ReportDetailsPageState();
}

class _ReportDetailsPageState extends State<ReportDetailsPage> {
  bool _updating = false;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.store,
    builder: (context, _) {
      final report = widget.store.reportById(widget.reportId);
      if (report == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Report details')),
          body: const EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Report not found',
            message: 'This report may have been removed.',
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(title: Text(report.id)),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            report.title,
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        StatusPill(status: report.status),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _DetailLine(
                      icon: Icons.location_on_outlined,
                      text: report.location,
                    ),
                    const SizedBox(height: 8),
                    _DetailLine(
                      icon: Icons.category_outlined,
                      text: report.category,
                    ),
                    const SizedBox(height: 8),
                    _DetailLine(
                      icon: Icons.flag_outlined,
                      text: '${report.priority.label} priority',
                    ),
                    if (report.assignee != null) ...[
                      const SizedBox(height: 8),
                      _DetailLine(
                        icon: Icons.person_outline_rounded,
                        text: 'Assigned to ${report.assignee}',
                      ),
                    ],
                    const SizedBox(height: 8),
                    _DetailLine(
                      icon: Icons.schedule_rounded,
                      text: _longDate(context, report.createdAt),
                    ),
                    const Divider(height: 26, color: _line),
                    const Text(
                      'Description',
                      style: TextStyle(
                        color: _ink,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      report.description,
                      style: const TextStyle(
                        color: Color(0xFF4E5B6D),
                        height: 1.5,
                      ),
                    ),
                    if (report.photoPath != null) ...[
                      const SizedBox(height: 16),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: SizedBox(
                          height: 200,
                          width: double.infinity,
                          child: ReportPhoto(path: report.photoPath!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.store.isMaintenance) ...[
              const SizedBox(height: 14),
              _ManagementControls(
                report: report,
                isUpdating: _updating,
                isAdmin: widget.store.isAdmin,
                onUpdate: _updateStatus,
              ),
            ],
            const SizedBox(height: 20),
            const SectionHeading(title: 'Activity'),
            const SizedBox(height: 8),
            ...report.activities.reversed.map(
              (activity) => _ActivityTile(activity: activity),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _updateStatus(
    ReportStatus status,
    String? assignee,
    ReportPriority? priority,
  ) async {
    setState(() => _updating = true);
    try {
      await widget.store.updateStatus(
        widget.reportId,
        status,
        assignee: assignee,
        priority: priority,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Report update saved.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update the report: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }
}

class _ManagementControls extends StatefulWidget {
  const _ManagementControls({
    required this.report,
    required this.isUpdating,
    required this.isAdmin,
    required this.onUpdate,
  });

  final MaintenanceReport report;
  final bool isUpdating;
  final bool isAdmin;
  final Future<void> Function(ReportStatus, String?, ReportPriority?) onUpdate;

  @override
  State<_ManagementControls> createState() => _ManagementControlsState();
}

class _ManagementControlsState extends State<_ManagementControls> {
  late ReportStatus _status;
  late ReportPriority _priority;
  late final TextEditingController _assigneeController;

  @override
  void initState() {
    super.initState();
    _status = widget.report.status;
    _priority = widget.report.priority;
    _assigneeController = TextEditingController(
      text: widget.report.assignedToEmail ?? widget.report.assignee ?? '',
    );
  }

  @override
  void didUpdateWidget(covariant _ManagementControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.report.status != widget.report.status) {
      _status = widget.report.status;
    }
    if (oldWidget.report.priority != widget.report.priority) {
      _priority = widget.report.priority;
    }
    if (oldWidget.report.assignedToEmail != widget.report.assignedToEmail ||
        oldWidget.report.assignee != widget.report.assignee) {
      _assigneeController.text =
          widget.report.assignedToEmail ?? widget.report.assignee ?? '';
    }
  }

  @override
  void dispose() {
    _assigneeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeading(title: 'Maintenance update'),
          const SizedBox(height: 10),
          DropdownButtonFormField<ReportStatus>(
            initialValue: _status,
            decoration: const InputDecoration(
              labelText: 'Report status',
              prefixIcon: Icon(Icons.sync_rounded),
            ),
            items: ReportStatus.values
                .map(
                  (status) => DropdownMenuItem(
                    value: status,
                    child: Text(status.label),
                  ),
                )
                .toList(),
            onChanged: widget.isUpdating
                ? null
                : (value) {
                    if (value != null) setState(() => _status = value);
                  },
          ),
          if (widget.isAdmin) ...[
            const SizedBox(height: 11),
            DropdownButtonFormField<ReportPriority>(
              initialValue: _priority,
              decoration: const InputDecoration(
                labelText: 'Priority',
                prefixIcon: Icon(Icons.flag_outlined),
              ),
              items: ReportPriority.values
                  .map(
                    (priority) => DropdownMenuItem(
                      value: priority,
                      child: Text(priority.label),
                    ),
                  )
                  .toList(),
              onChanged: widget.isUpdating
                  ? null
                  : (value) {
                      if (value != null) setState(() => _priority = value);
                    },
            ),
            const SizedBox(height: 11),
            TextField(
              controller: _assigneeController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Maintenance staff email (blank to unassign)',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'Only an approved maintenance account can be assigned.',
              style: TextStyle(color: _muted, fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: widget.isUpdating
                ? null
                : () => widget.onUpdate(
                    _status,
                    widget.isAdmin ? _assigneeController.text.trim() : null,
                    widget.isAdmin ? _priority : null,
                  ),
            child: Text(
              widget.isUpdating
                  ? 'Saving…'
                  : widget.isAdmin
                  ? 'Save report changes'
                  : 'Save progress',
            ),
          ),
        ],
      ),
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 17, color: _muted),
      const SizedBox(width: 8),
      Expanded(
        child: Text(text, style: const TextStyle(color: _muted, fontSize: 12)),
      ),
    ],
  );
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.activity});

  final ReportActivity activity;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            color: Color(0xFFE6F4EF),
            shape: BoxShape.circle,
          ),
          child: Icon(
            activity.status == ReportStatus.resolved
                ? Icons.check_rounded
                : Icons.more_horiz_rounded,
            color: _green,
            size: 17,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                activity.message,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _longDate(context, activity.createdAt),
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({required this.store, super.key});

  final LocalStore store;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _markRead();
    });
  }

  Future<void> _markRead() async {
    try {
      await widget.store.markNotificationsRead();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update notifications: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Notifications')),
    body: AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final notifications = widget.store.notifications;
        if (notifications.isEmpty) {
          return const EmptyState(
            icon: Icons.notifications_none_rounded,
            title: 'You’re all caught up',
            message: 'Status updates for your reports will appear here.',
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
          children: notifications.map((notification) {
            final report = widget.store.reportById(notification.reportId);
            return Card(
              child: ListTile(
                onTap: report == null
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => ReportDetailsPage(
                            store: widget.store,
                            reportId: report.id,
                          ),
                        ),
                      ),
                contentPadding: const EdgeInsets.all(13),
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: notification.isRead
                        ? const Color(0xFFF0F2F4)
                        : const Color(0xFFE6F4EF),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.notifications_active_outlined,
                    color: _green,
                  ),
                ),
                title: Text(
                  notification.title,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(
                    '${notification.message}\n${_shortDate(context, notification.createdAt)}',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ),
                isThreeLine: true,
                trailing: notification.isRead
                    ? null
                    : const Icon(Icons.circle, color: _green, size: 9),
              ),
            );
          }).toList(),
        );
      },
    ),
  );
}

class ProfilePage extends StatefulWidget {
  const ProfilePage({required this.store, this.onLogout, super.key});

  final LocalStore store;
  final VoidCallback? onLogout;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late UserRole _role;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.store.displayName);
    _emailController = TextEditingController(text: widget.store.email);
    _role = widget.store.role;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 26),
    children: [
      const Text(
        'Profile & settings',
        style: TextStyle(
          color: _ink,
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeading(title: 'Your profile'),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Display name',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                readOnly: FirebaseService.isReady,
                decoration: const InputDecoration(
                  labelText: 'Email address',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
              ),
              if (FirebaseService.isReady) ...[
                const SizedBox(height: 16),
                Text(
                  'Firebase access role: ${widget.store.role.label}',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 20),
                const Text(
                  'Demo access',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                SegmentedButton<UserRole>(
                  segments: UserRole.values
                      .map(
                        (role) =>
                            ButtonSegment(value: role, label: Text(role.label)),
                      )
                      .toList(),
                  selected: {_role},
                  onSelectionChanged: (selection) =>
                      setState(() => _role = selection.first),
                ),
                const SizedBox(height: 9),
                const Text(
                  'Maintenance tools are available in this local demo only. '
                  'Production access must be verified by Firebase security rules.',
                  style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _saveProfile,
                child: Text(_saving ? 'Saving…' : 'Save profile'),
              ),
              if (widget.onLogout != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Log out'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: const Color(0xFFB91C1C),
                    side: const BorderSide(color: Color(0xFFFCA5A5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    FirebaseService.isReady
                        ? Icons.cloud_done_outlined
                        : Icons.cloud_off_outlined,
                    color: FirebaseService.isReady
                        ? const Color(0xFF146C43)
                        : const Color(0xFF98651B),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    FirebaseService.isReady
                        ? 'Firebase connected'
                        : 'Local demo mode',
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                FirebaseService.isReady
                    ? 'Sign-in, reports, and profile updates use Firebase Authentication and Cloud Firestore. '
                          'Photo files are still stored only on this device.'
                    : 'Reports and profile details are stored on this device. '
                          'Firebase is not configured for this platform.',
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      await widget.store.updateProfile(
        displayName: _nameController.text,
        email: _emailController.text,
        role: _role,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              FirebaseService.isReady
                  ? 'Profile saved to Firebase.'
                  : 'Profile saved on this device.',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save profile: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 28),
    child: Column(
      children: [
        Icon(icon, size: 43, color: const Color(0xFF9AA5B3)),
        const SizedBox(height: 13),
        Text(
          title,
          style: const TextStyle(
            color: _ink,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 12, height: 1.45),
        ),
      ],
    ),
  );
}

class ReportPhoto extends StatefulWidget {
  const ReportPhoto({required this.path, super.key});

  final String path;

  @override
  State<ReportPhoto> createState() => _ReportPhotoState();
}

class _ReportPhotoState extends State<ReportPhoto> {
  Future<Uint8List?>? _photo;

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  @override
  void didUpdateWidget(covariant ReportPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _loadPhoto();
  }

  void _loadPhoto() {
    _photo = FirebaseService.isReady && widget.path.startsWith('reports/')
        ? FirebaseService.storage.ref(widget.path).getData(10 * 1024 * 1024)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    if (_photo == null) {
      return _imageForPath(widget.path, fit: BoxFit.cover);
    }
    return FutureBuilder<Uint8List?>(
      future: _photo,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Photo could not be loaded.'));
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return snapshot.connectionState == ConnectionState.waiting
              ? const Center(child: CircularProgressIndicator())
              : const Center(child: Text('Photo is unavailable.'));
        }
        return Image.memory(bytes, fit: BoxFit.cover);
      },
    );
  }
}

Widget _imageForPath(String path, {required BoxFit fit}) {
  if (path.startsWith('data:image/')) {
    final separator = path.indexOf(',');
    if (separator < 0) {
      return const Center(child: Text('Photo is unavailable.'));
    }
    try {
      return Image.memory(
        base64Decode(path.substring(separator + 1)),
        fit: fit,
      );
    } on FormatException {
      return const Center(child: Text('Photo is unavailable.'));
    }
  }
  final scheme = Uri.tryParse(path)?.scheme;
  if (kIsWeb || scheme == 'http' || scheme == 'https') {
    return Image.network(path, fit: fit);
  }
  return Image.file(File(path), fit: fit);
}

String _shortDate(BuildContext context, DateTime date) {
  final now = DateTime.now();
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return TimeOfDay.fromDateTime(date).format(context);
  }
  return MaterialLocalizations.of(context).formatShortDate(date);
}

String _longDate(BuildContext context, DateTime date) =>
    '${MaterialLocalizations.of(context).formatMediumDate(date)} · '
    '${TimeOfDay.fromDateTime(date).format(context)}';
