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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create account')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(controller: _name, decoration: const InputDecoration(labelText: 'Full name'), validator: (value) => value == null || value.trim().isEmpty ? 'Enter your full name.' : null),
                  const SizedBox(height: 14),
                  TextFormField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email'), validator: (value) => value == null || !value.contains('@') ? 'Enter a valid email.' : null),
                  const SizedBox(height: 14),
                  TextFormField(controller: _password, obscureText: true, decoration: const InputDecoration(labelText: 'Password'), validator: (value) => value == null || value.length < 6 ? 'Password must be at least 6 characters.' : null),
                  const SizedBox(height: 14),
                  TextFormField(controller: _confirm, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password'), validator: (value) => value != _password.text ? 'Passwords do not match.' : null),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  const SizedBox(height: 22),
                  FilledButton(onPressed: _loading ? null : _submit, child: _loading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Register')),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}