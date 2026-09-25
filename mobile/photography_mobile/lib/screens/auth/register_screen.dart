import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/auth_session.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, required this.session});
  final AuthSession session;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await widget.session.register(fullName: _name.text, email: _email.text, password: _password.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account created. Please log in.')));
        Navigator.of(context).pop();
      }
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF075866);
    const accent = Color(0xFF12C9D2);
    const ink = Color(0xFF202126);

    InputDecoration field(String label, IconData icon) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF858589)),
      prefixIcon: Icon(icon, color: const Color(0xFF77777D), size: 21),
      filled: true,
      fillColor: const Color(0xFFF7F7F7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: const BorderSide(color: accent, width: 1.5),
      ),
      errorMaxLines: 2,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFDFF6F7),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          color: teal,
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(40)),
                        ),
                        padding: const EdgeInsets.fromLTRB(28, 30, 28, 76),
                        child: const Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.camera_alt_outlined, color: Color(0xFFB9F4F4), size: 25),
                              SizedBox(width: 9),
                              Text('SnapSync', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                            ]),
                            SizedBox(height: 64),
                            Text('Hello, Welcome', style: TextStyle(color: Colors.white, fontSize: 31, fontWeight: FontWeight.w700)),
                            SizedBox(height: 8),
                            Text('Create your account', style: TextStyle(color: Color(0xFFD5F1F1), fontSize: 16)),
                          ],
                        ),
                      ),
                      Transform.translate(
                        offset: const Offset(0, -36),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            padding: const EdgeInsets.all(24),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [BoxShadow(color: teal.withValues(alpha: .12), blurRadius: 32, offset: const Offset(0, 12))],
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text('Register', style: TextStyle(color: ink, fontSize: 28, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 22),
                                  TextFormField(controller: _name, decoration: field('Full name', Icons.person_outline_rounded), validator: (value) => value == null || value.trim().isEmpty ? 'Enter your full name.' : null),
                                  const SizedBox(height: 14),
                                  TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: field('Email', Icons.mail_outline_rounded), validator: (value) => value == null || !value.contains('@') ? 'Enter a valid email.' : null),
                                  const SizedBox(height: 14),
                                  TextFormField(controller: _password, obscureText: true, decoration: field('Password', Icons.lock_outline_rounded), validator: (value) => value == null || value.length < 6 ? 'Password must be at least 6 characters.' : null),
                                  const SizedBox(height: 14),
                                  TextFormField(controller: _confirm, obscureText: true, decoration: field('Confirm password', Icons.lock_outline_rounded), validator: (value) => value != _password.text ? 'Passwords do not match.' : null),
                                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                                  const SizedBox(height: 22),
                                  DecoratedBox(
                                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF087B87), accent]), borderRadius: BorderRadius.circular(16)),
                                    child: FilledButton(
                                      style: FilledButton.styleFrom(backgroundColor: Colors.transparent, disabledBackgroundColor: Colors.transparent, foregroundColor: Colors.white, shadowColor: Colors.transparent, minimumSize: const Size.fromHeight(56), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                      onPressed: _loading ? null : _submit,
                                      child: _loading ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Register'),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
                                    const Text('Already have an account?', style: TextStyle(color: Color(0xFF777181))),
                                    TextButton(onPressed: _loading ? null : () => Navigator.of(context).pop(), child: const Text('Login', style: TextStyle(color: teal, fontWeight: FontWeight.w700))),
                                  ]),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
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