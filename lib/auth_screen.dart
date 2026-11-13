import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dashboard_screen.dart';
import 'shop_config.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _shopNameController = TextEditingController();
  final _ownerEmailController = TextEditingController();
  bool _isSignUp = false;
  bool _isStaffSignUp = false;
  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _shopNameController.dispose();
    _ownerEmailController.dispose();
    super.dispose();
  }

  void _showPendingApprovalDialog(String email) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lock_clock_rounded, color: Colors.orange, size: 26),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Approval Required',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Account "$email" is currently set to:',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFECACA)),
              ),
              child: const Text(
                'is_approved = FALSE (Default Security Lock)',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Color(0xFFDC2626),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'How to Approve:\n'
              '• Shop Owners: Approved by Database Admin in Supabase user_profiles.\n'
              '• Shop Staff / Cashiers: Your Shop Owner can approve your account directly from their Dashboard → "Staff & PIN" button.',
              style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.45),
            ),
          ],
        ),
        actions: [
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: email));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Email copied!')),
              );
            },
            icon: const Icon(Icons.copy, size: 15),
            label: const Text('Copy Email'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF4338CA)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Understood'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final shopName = _shopNameController.text.trim();
    final ownerEmail = _ownerEmailController.text.trim();

    if (email.isEmpty || password.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email and 6+ character password.')),
      );
      return;
    }

    if (_isSignUp && !_isStaffSignUp && shopName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your Shop Name for billing receipts.')),
      );
      return;
    }

    if (_isSignUp && _isStaffSignUp && ownerEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter your Shop Owner's registered email.")),
      );
      return;
    }

    setState(() => _loading = true);
    final supabase = Supabase.instance.client;

    try {
      if (_isSignUp) {
        await supabase.auth.signUp(
          email: email,
          password: password,
          data: {
            'shop_name': shopName,
            'role': _isStaffSignUp ? 'cashier' : 'shop_owner',
            'owner_email': _isStaffSignUp ? ownerEmail : '',
          },
        );
        // Immediately sign out so unapproved user cannot enter app
        await supabase.auth.signOut();
        if (mounted) {
          setState(() => _isSignUp = false);
          _showPendingApprovalDialog(email);
        }
      } else {
        await supabase.auth.signInWithPassword(email: email, password: password);
        final user = supabase.auth.currentUser;

        if (user != null) {
          final profile = await supabase
              .from('user_profiles')
              .select('is_approved')
              .eq('id', user.id)
              .maybeSingle();

          if (profile == null || profile['is_approved'] != true) {
            await supabase.auth.signOut();
            if (mounted) {
              _showPendingApprovalDialog(email);
            }
            return;
          }

          await ShopConfig.loadFromDatabase();

          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const DashboardScreen()),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Authentication error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 12,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 430),
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: const BoxDecoration(
                      color: Color(0xFFEEF2FF),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.storefront_rounded,
                      size: 54,
                      color: Color(0xFF4338CA),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isSignUp ? 'Create Store Account' : 'Store Management Login',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isSignUp
                        ? 'Register as a Shop Owner or link as a Shop Employee / Cashier'
                        : 'Sign in as Shop Owner (Full Access) or Shop Staff (Inventory & POS)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  if (_isSignUp) ...[
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('Shop Owner', style: TextStyle(fontSize: 12)),
                            icon: Icon(Icons.admin_panel_settings_outlined, size: 16),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('Shop Employee', style: TextStyle(fontSize: 12)),
                            icon: Icon(Icons.badge_outlined, size: 16),
                          ),
                        ],
                        selected: {_isStaffSignUp},
                        onSelectionChanged: (s) => setState(() => _isStaffSignUp = s.first),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!_isStaffSignUp)
                      TextField(
                        controller: _shopNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Your Shop / Showroom Name',
                          hintText: 'e.g. Royal Mobile World',
                          prefixIcon: const Icon(Icons.store_mall_directory_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      )
                    else
                      TextField(
                        controller: _ownerEmailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: "Shop Owner's Registered Email",
                          hintText: 'owner@shop.com',
                          prefixIcon: const Icon(Icons.supervisor_account_outlined),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: _isSignUp && _isStaffSignUp
                          ? 'Employee Email Address'
                          : 'Store Email Address',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 20,
                        ),
                        onPressed: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: const Color(0xFF4338CA),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _loading ? null : _submit,
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(
                            _isSignUp
                                ? (_isStaffSignUp ? 'Register as Employee' : 'Register My Shop')
                                : 'Sign In to Store',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => setState(() => _isSignUp = !_isSignUp),
                    child: Text(
                      _isSignUp
                          ? 'Already registered? Sign In'
                          : "Don't have an account? Register here",
                      style: const TextStyle(color: Color(0xFF4338CA)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}