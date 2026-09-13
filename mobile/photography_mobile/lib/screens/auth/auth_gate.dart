import 'package:flutter/material.dart';

import '../../services/auth_session.dart';
import '../customer/customer_shell.dart';
import 'login_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final AuthSession _session = AuthSession()..restore();

  @override
  void dispose() {
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _session,
    builder: (context, _) {
      if (_session.isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
      if (_session.user == null) return LoginScreen(session: _session);
      return CustomerShell(session: _session);
    },
  );
}