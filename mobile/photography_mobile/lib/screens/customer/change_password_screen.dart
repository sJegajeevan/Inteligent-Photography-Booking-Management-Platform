import 'dart:convert';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _service = AuthService();
  final _form = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _new = TextEditingController();
  final _confirm = TextEditingController();
  final _hidden = [true, true, true];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose(); _new.dispose(); _confirm.dispose();
    _service.close();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() { _saving = true; _error = null; });
    try {
      await _service.changePassword(currentPassword: _current.text, newPassword: _new.text, confirmPassword: _confirm.text);
      if (!mounted) return;
      _form.currentState!.reset();
      _current.clear(); _new.clear(); _confirm.clear();
      setState(() { _hidden.fillRange(0, _hidden.length, true); });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password changed successfully. You are still signed in.')));
    } on AuthApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to change your password. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(String label, TextEditingController controller, int index, String? Function(String?) validator) => TextFormField(
    controller: controller,
    enabled: !_saving,
    obscureText: _hidden[index],
    autocorrect: false,
    enableSuggestions: false,
    keyboardType: TextInputType.visiblePassword,
    textInputAction: index == 2 ? TextInputAction.done : TextInputAction.next,
    onFieldSubmitted: index == 2 ? (_) => _save() : null,
    decoration: InputDecoration(labelText: label,
      prefixIcon: const Icon(Icons.lock_outline),
      suffixIcon: IconButton(onPressed: _saving ? null : () => setState(() => _hidden[index] = !_hidden[index]),
        tooltip: '${_hidden[index] ? 'Show' : 'Hide'} ${label.toLowerCase()}',
        icon: Icon(_hidden[index] ? Icons.visibility_outlined : Icons.visibility_off_outlined))),
    validator: validator,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PopScope(canPop: !_saving, child: Scaffold(
      appBar: AppBar(title: const Text('Change Password')),
      body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620),
        child: Form(key: _form, child: ListView(padding: const EdgeInsets.all(24), children: [
          Container(padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: colors.primaryContainer.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(24)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.key_rounded, color: colors.primary, size: 32),
              const SizedBox(height: 12),
              Text('A fresh password', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Choose a password of at least 6 characters. Use one you do not use for other accounts.'),
            ]),
          ),
          const SizedBox(height: 28),
          _field('Current Password', _current, 0, (value) => value == null || value.trim().isEmpty ? 'Enter your current password.' : null),
          const SizedBox(height: 18),
          _field('New Password', _new, 1, (value) {
            if (value == null || value.trim().isEmpty || value.length < 6) return 'Use at least 6 characters.';
            if (utf8.encode(value).length > 72) return 'Password is too long. Use fewer characters.';
            return null;
          }),
          const SizedBox(height: 18),
          _field('Confirm New Password', _confirm, 2, (value) => value == null || value.isEmpty ? 'Confirm your new password.' : value != _new.text ? 'Passwords do not match.' : null),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 18), child: Text(_error!, style: TextStyle(color: colors.error))),
          const SizedBox(height: 26),
          FilledButton.icon(onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
            label: Text(_saving ? 'Saving...' : 'Change Password')),
        ])),
      ))),
    ));
  }
}
