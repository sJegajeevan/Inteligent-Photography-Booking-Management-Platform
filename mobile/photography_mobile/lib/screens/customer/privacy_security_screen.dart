import 'package:flutter/material.dart';
import '../../services/auth_session.dart';
import 'change_password_screen.dart';

class PrivacySecurityScreen extends StatelessWidget {
  const PrivacySecurityScreen({super.key, required this.session});
  final AuthSession session;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: session, builder: (context, _) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final user = session.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Security')),
      body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620),
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Container(padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(colors: [colors.primaryContainer, colors.surfaceContainerLow])),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.shield_outlined, color: colors.primary, size: 34),
              const SizedBox(height: 14),
              Text('Your account, protected', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              const Text('Manage your password and check the account you are signed in with.'),
            ]),
          ),
          const SizedBox(height: 26),
          Text('Signed-in account', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Card(margin: EdgeInsets.zero, child: Column(children: [
            ListTile(leading: Icon(Icons.person_outline, color: colors.primary), title: const Text('Full name'), subtitle: Text(user?.fullName ?? 'Not signed in')),
            ListTile(leading: Icon(Icons.mail_outline, color: colors.primary), title: const Text('Email'), subtitle: Text(user?.email ?? 'Not signed in')),
            ListTile(leading: Icon(Icons.badge_outlined, color: colors.primary), title: const Text('Account type'), subtitle: Text(user?.role ?? 'Not signed in')),
          ])),
          const SizedBox(height: 26),
          Text('Password', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias, child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Icon(Icons.lock_outline, color: colors.primary),
            title: const Text('Change Password', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Requires your current password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: user == null ? null : () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const ChangePasswordScreen())),
          )),
          const SizedBox(height: 16),
          Text('Changing your password keeps your current session signed in. It does not sign out other active sessions.',
            style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        ]),
      ))),
    );
  });
}
