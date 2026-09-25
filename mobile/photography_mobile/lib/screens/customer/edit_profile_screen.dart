import 'package:flutter/material.dart';
import '../../services/auth_session.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, required this.session});
  final AuthSession session;

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      await widget.session.refreshProfile();
      if (!mounted) return;
      final user = widget.session.user;
      _name.text = user?.fullName ?? '';
      _email.text = user?.email ?? '';
      _phone.text = user?.phoneNumber ?? '';
      setState(() => _loading = false);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() { _saving = true; _error = null; });
    try {
      await widget.session.updateProfile(fullName: _name.text, email: _email.text, phoneNumber: _phone.text);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) setState(() { _error = error.toString(); _saving = false; });
    }
  }

  @override
  void dispose() {
    _name.dispose(); _email.dispose(); _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: _loading
          ? Center(child: _error == null ? const CircularProgressIndicator() : Padding(
              padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(_error!, textAlign: TextAlign.center),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ])))
          : Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620), child: Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(24), children: [
                Text('Make it yours', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                const Text('Keep your details up to date for your next photography session.'),
                const SizedBox(height: 28),
                TextFormField(controller: _name, enabled: !_saving, maxLength: 160,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline)),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Full name is required.' : null),
                const SizedBox(height: 16),
                TextFormField(controller: _email, enabled: !_saving, maxLength: 254,
                  keyboardType: TextInputType.emailAddress, autocorrect: false,
                  decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline)),
                  validator: (value) => value == null || !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim()) ? 'Enter a valid email address.' : null),
                const SizedBox(height: 16),
                TextFormField(controller: _phone, enabled: !_saving, maxLength: 30,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone number (optional)', prefixIcon: Icon(Icons.phone_outlined)),
                  validator: (value) => value == null || value.trim().isEmpty || RegExp(r'^\+?[0-9 ()\-]{7,30}$').hasMatch(value.trim()) ? null : 'Enter a valid phone number.'),
                if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                const SizedBox(height: 24),
                FilledButton.icon(onPressed: _saving ? null : _save,
                  icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                  label: Text(_saving ? 'Saving…' : 'Save changes')),
              ]),
            ))),
    ),
  );
}
