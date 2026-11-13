import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_screen.dart';
import 'dashboard_screen.dart';
import 'shop_config.dart';

const String supabaseUrl =
    'https://zjvflhqawvbntpteikje.supabase.co';

const String supabaseAnonKey =
   'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpqdmZsaHFhd3ZibnRwdGVpa2plIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTIyNDI3MzMsImV4cCI6MjEwNzgxODczM30.CkN7ftF-xU9wLsBIaLJha4TjD9wKopdHxjYtMjJ-HbY';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );

    runApp(const MobileShopApp());
  } catch (error, stackTrace) {
    debugPrint('Supabase initialization failed: $error');
    debugPrintStack(stackTrace: stackTrace);

    runApp(
      StartupErrorApp(error: error.toString()),
    );
  }
}

class MobileShopApp extends StatefulWidget {
  const MobileShopApp({super.key});

  @override
  State<MobileShopApp> createState() => _MobileShopAppState();
}

class _MobileShopAppState extends State<MobileShopApp> {
  bool _isLoading = true;
  bool _isApproved = false;
  bool _isAuthenticated = false;

  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _checkInitialAuth();
    _listenToAuthChanges();
  }

  Future<void> _checkInitialAuth() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase = Supabase.instance.client;
      final session = supabase.auth.currentSession;
      final user = supabase.auth.currentUser;

      if (session == null || user == null) {
        if (!mounted) return;

        setState(() {
          _isAuthenticated = false;
          _isApproved = false;
          _isLoading = false;
        });
        return;
      }

      final profile = await supabase
          .from('user_profiles')
          .select(
            'is_approved, shop_name, shop_phone, shop_address, role',
          )
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 15));

      final bool approved =
          profile != null && profile['is_approved'] == true;

      if (!approved) {
        await supabase.auth.signOut();

        if (!mounted) return;

        setState(() {
          _isAuthenticated = false;
          _isApproved = false;
          _isLoading = false;
        });
        return;
      }

      await ShopConfig.loadFromDatabase()
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      setState(() {
        _isAuthenticated = true;
        _isApproved = true;
        _isLoading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Authentication check failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _isAuthenticated = false;
        _isApproved = false;
        _isLoading = false;
        _errorMessage = error.toString();
      });
    }
  }

  void _listenToAuthChanges() {
    Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        if (data.event == AuthChangeEvent.signedIn) {
          _checkInitialAuth();
        } else if (data.event == AuthChangeEvent.signedOut) {
          if (!mounted) return;

          setState(() {
            _isAuthenticated = false;
            _isApproved = false;
            _isLoading = false;
            _errorMessage = null;
          });
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Auth state listener error: $error');
        debugPrintStack(stackTrace: stackTrace);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile POS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4338CA),
          primary: const Color(0xFF4338CA),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
      ),
      home: _isLoading
          ? const LoadingScreen()
          : _errorMessage != null
              ? ErrorScreen(
                  message: _errorMessage!,
                  onRetry: _checkInitialAuth,
                )
              : (_isAuthenticated && _isApproved)
                  ? const DashboardScreen()
                  : const AuthScreen(),
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(
              color: Color(0xFF4338CA),
            ),
            SizedBox(height: 16),
            Text(
            'Mobile POS',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Text('Loading... Please wait'),
          ],
        ),
      ),
    );
  }
}

class ErrorScreen extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const ErrorScreen({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mobile POS'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 64,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Something went wrong',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                SelectableText(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try Again'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StartupErrorApp extends StatelessWidget {
  final String error;

  const StartupErrorApp({
    super.key,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mobile POS',
      debugShowCheckedModeBanner: false,
      home: ErrorScreen(
        message: 'Supabase initialization failed:\n$error',
        onRetry: () {
          // Restart the app manually after fixing the configuration.
        },
      ),
    );
  }
}