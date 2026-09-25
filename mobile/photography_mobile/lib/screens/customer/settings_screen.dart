import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/app_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<PackageInfo> _info = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AppSettings.instance,
    builder: (context, _) {
      final settings = AppSettings.instance;
      final theme = Theme.of(context);
      final colors = theme.colorScheme;
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: SafeArea(child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 620),
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Container(padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(colors: [colors.primaryContainer, colors.surfaceContainerLow])),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.tune_rounded, color: colors.primary, size: 32),
                const SizedBox(height: 14),
                Text('Your SnapSync', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('A little more you. Choose how the app looks on this device.'),
              ]),
            ),
            const SizedBox(height: 28),
            Text('Appearance', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Card(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias, child: Column(children: [
              for (final mode in ThemeMode.values) ListTile(
                enabled: !settings.saving,
                onTap: settings.saving ? null : () => settings.setTheme(mode),
                leading: Icon(switch (mode) {
                  ThemeMode.system => Icons.brightness_auto_outlined,
                  ThemeMode.light => Icons.light_mode_outlined,
                  ThemeMode.dark => Icons.dark_mode_outlined,
                }, color: colors.primary),
                title: Text(switch (mode) {
                  ThemeMode.system => 'System', ThemeMode.light => 'Light', ThemeMode.dark => 'Dark',
                }),
                subtitle: mode == ThemeMode.system ? const Text('Follow your device appearance') : null,
                selected: settings.themeMode == mode,
                selectedTileColor: colors.primaryContainer.withValues(alpha: 0.35),
                trailing: settings.themeMode == mode ? Icon(Icons.check_circle, color: colors.primary) : null,
              ),
              if (settings.saving) const LinearProgressIndicator(),
            ])),
            const SizedBox(height: 10),
            Text('Saved on this device, including after you log out.', style: theme.textTheme.bodySmall),
            if (settings.error != null) Padding(padding: const EdgeInsets.only(top: 12),
              child: Text(settings.error!, style: TextStyle(color: colors.error))),
            const SizedBox(height: 28),
            Text('About SnapSync', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Card(margin: EdgeInsets.zero, child: Padding(padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [Icon(Icons.camera_alt_outlined, color: colors.primary), const SizedBox(width: 10),
                  Text('SnapSync', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))]),
                const SizedBox(height: 8),
                const Text('Photography booking for your next memorable moment.'),
                const SizedBox(height: 16),
                FutureBuilder<PackageInfo>(future: _info, builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) return const LinearProgressIndicator();
                  if (snapshot.hasError || snapshot.data == null) return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('App version is unavailable.'),
                    TextButton(onPressed: () => setState(() => _info = PackageInfo.fromPlatform()), child: const Text('Retry')),
                  ]);
                  final info = snapshot.data!;
                  return Text('Version ${info.version}${info.buildNumber.isEmpty ? '' : ' · Build ${info.buildNumber}'}', style: theme.textTheme.bodyMedium);
                }),
              ]),
            )),
          ]),
        ))),
      );
    },
  );
}
