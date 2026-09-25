import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_config.dart';
import 'edit_profile_screen.dart';
import '../../services/notification_service.dart';
import 'notifications_screen.dart';
import 'settings_screen.dart';
import 'privacy_security_screen.dart';

import '../../models/studio.dart';
import '../../services/auth_session.dart';
import '../../services/studio_service.dart';
import '../../widgets/studio_card.dart';
import '../studio/studio_detail_screen.dart';
import '../studio/studio_list_screen.dart';
import '../booking/my_bookings_screen.dart';
import '../ai/ai_workflow_screens.dart';

class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key, required this.session});
  final AuthSession session;

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  late final StudioService _studioService = StudioService();
  int _index = 0;

  @override
  void dispose() {
    _studioService.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      CustomerDashboard(userName: widget.session.user?.fullName ?? '', service: _studioService),
      StudioListScreen(service: _studioService),
      _ProfileScreen(session: widget.session, isActive: _index == 2),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        indicatorColor: const Color(0xFFE8D9FF),
        labelTextStyle: const WidgetStatePropertyAll(TextStyle(color: Color(0xFF4B3A7C), fontWeight: FontWeight.w600)),
        indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        elevation: 2,
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'Studios'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class CustomerDashboard extends StatefulWidget {
  const CustomerDashboard({super.key, required this.userName, required this.service});
  final String userName;
  final StudioService service;

  @override
  State<CustomerDashboard> createState() => _CustomerDashboardState();
}

class _CustomerDashboardState extends State<CustomerDashboard> {
  static const _types = ['Wedding', 'Pre-Wedding', 'Birthday', 'Event', 'Portrait', 'Product'];
  late Future<List<Studio>> _studios;
  final _search = TextEditingController();
  final _location = TextEditingController();
  final _minBudget = TextEditingController();
  final _maxBudget = TextEditingController();
  String? _type;
  DateTime? _eventDate;

  @override
  void initState() {
    super.initState();
    _studios = widget.service.getStudios();
  }

  @override
  void dispose() {
    _search.dispose();
    _location.dispose();
    _minBudget.dispose();
    _maxBudget.dispose();
    super.dispose();
  }

  void _retry() => setState(() => _studios = widget.service.getStudios());

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
      initialDate: _eventDate ?? DateTime.now(),
    );
    if (date != null) setState(() => _eventDate = date);
  }

  List<Studio> _filtered(List<Studio> studios) {
    final query = _search.text.trim().toLowerCase();
    final location = _location.text.trim().toLowerCase();
    final min = double.tryParse(_minBudget.text.trim());
    final max = double.tryParse(_maxBudget.text.trim());
    return studios.where((studio) {
      final matchesSearch = query.isEmpty || studio.matches(query);
      final matchesLocation = location.isEmpty || studio.location.toLowerCase().contains(location);
      final matchesType = _type == null || studio.photographyTypes.any((value) => value.toLowerCase().contains(_type!.toLowerCase()));
      final price = studio.startingPrice;
      final matchesMin = min == null || (price != null && price >= min);
      final matchesMax = max == null || (price != null && price <= max);
      return matchesSearch && matchesLocation && matchesType && matchesMin && matchesMax;
    }).toList();
  }

  String _dateLabel() {
    final date = _eventDate;
    if (date == null) return 'Event date';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF3F5FF),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AiWorkflowsScreen())),
      icon: const Icon(Icons.auto_awesome), label: const Text('Find with AI')),
    body: SafeArea(
      child: FutureBuilder<List<Studio>>(
        future: _studios,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError) return _DashboardError(error: snapshot.error!, onRetry: _retry);
          final studios = _filtered(snapshot.data ?? const []);
          return RefreshIndicator(
            onRefresh: () async => _retry(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(30, 18, 30, 34),
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 25),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .78),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: const [BoxShadow(color: Color(0x1A423A72), blurRadius: 24, offset: Offset(0, 10))],
                  ),
                  child: Stack(
                    children: [
                      const Positioned.fill(child: _HeroImage()),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Padding(padding: EdgeInsets.fromLTRB(24, 28, 24, 0), child: Text('Find your studio', style: TextStyle(color: Colors.white, fontSize: 27, fontWeight: FontWeight.w400))),
                          const SizedBox(height: 58),
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text.rich(TextSpan(children: [
                            const TextSpan(text: 'Hello, ', style: TextStyle(color: Color(0xFF202039))),
                            TextSpan(text: widget.userName.isEmpty ? 'there' : widget.userName.split(' ').first, style: const TextStyle(color: Color(0xFFC69BFF))),
                          ]), style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w800))),
                          const SizedBox(height: 5),
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Let us find the right place for your next story.', style: TextStyle(color: Color(0xFF555873), fontSize: 16))),
                          const SizedBox(height: 27),
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: TextField(controller: _search, onChanged: (_) => setState(() {}), style: const TextStyle(fontSize: 18, color: Color(0xFF26263F)), decoration: _field('Search studios', Icons.search, filled: true))),
                          const SizedBox(height: 25),
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Photography preference', style: TextStyle(color: Color(0xFF202039), fontSize: 18, fontWeight: FontWeight.w800))),
                          const SizedBox(height: 13),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Wrap(spacing: 8, runSpacing: 10, children: _types.asMap().entries.map((entry) => _PreferenceChip(type: entry.value, index: entry.key, selected: _type == entry.value, onSelected: (selected) => setState(() => _type = selected ? entry.value : null))).toList()),
                          ),
                          const SizedBox(height: 25),
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: TextField(controller: _location, onChanged: (_) => setState(() {}), style: const TextStyle(fontSize: 18, color: Color(0xFF26263F)), decoration: _field('Location', Icons.location_on_outlined, filled: true))),
                          const SizedBox(height: 14),
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(children: [Expanded(child: TextField(controller: _minBudget, onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, decoration: _field('Min budget', Icons.monetization_on_outlined, filled: true))), const SizedBox(width: 12), Expanded(child: TextField(controller: _maxBudget, onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, decoration: _field('Max budget', Icons.monetization_on_outlined, filled: true)))])),
                          const SizedBox(height: 14),
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: OutlinedButton.icon(onPressed: _chooseDate, icon: const Icon(Icons.calendar_month_outlined), label: Text(_dateLabel()), style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF52536D), alignment: Alignment.centerLeft, backgroundColor: Colors.white, side: BorderSide.none, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))))),
                          const SizedBox(height: 20),
                          Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: FilledButton.icon(onPressed: () => setState(() {}), icon: const Icon(Icons.search), label: const Text('Find studios'), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF6040C2), foregroundColor: Colors.white, minimumSize: const Size.fromHeight(58), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)))),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Recommended studios', style: TextStyle(color: Color(0xFF202039), fontSize: 20, fontWeight: FontWeight.bold)), Text('${studios.length} found', style: const TextStyle(color: Color(0xFF65657B)))]),
                const SizedBox(height: 12),
                if (snapshot.data!.isEmpty) const Text('No studios are available yet.'),
                if (snapshot.data!.isNotEmpty && studios.isEmpty) const Text('No studios match these filters. Try widening your search.'),
                ...studios.take(5).map((studio) => StudioCard(studio: studio, onView: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => StudioDetailScreen(studioId: studio.id, service: widget.service))))),
              ],
            ),
          );
        },
      ),
    ),
  );
}

InputDecoration _field(String hint, IconData? icon, {required bool filled}) => InputDecoration(
  hintText: hint,
  prefixIcon: icon == null ? null : Icon(icon, color: const Color(0xFF35354F), size: 27),
  filled: filled,
  fillColor: Colors.white,
  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: Color(0xFF8D66E8), width: 1.5)),
);

class _PreferenceChip extends StatelessWidget {
  const _PreferenceChip({required this.type, required this.index, required this.selected, required this.onSelected});
  final String type;
  final int index;
  final bool selected;
  final ValueChanged<bool> onSelected;

  static const _images = [
    'https://images.unsplash.com/photo-1519225421980-715cb0215aed?w=500',
    'https://images.unsplash.com/photo-1516589178581-6cd7833ae3b2?w=500',
    'https://images.unsplash.com/photo-1578985545062-69928b1d9587?w=500',
    'https://images.unsplash.com/photo-1506157786151-b8491531f063?w=500',
    'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=500',
    'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=500',
  ];
  static const _icons = [Icons.favorite_border, Icons.groups_outlined, Icons.cake_outlined, Icons.event_outlined, Icons.person_outline, Icons.inventory_2_outlined];

  @override
  Widget build(BuildContext context) {
    final tileWidth = ((MediaQuery.sizeOf(context).width - 92) / 2).clamp(130.0, 210.0);
    return GestureDetector(
    onTap: () => onSelected(!selected),
    child: Container(
      width: tileWidth,
      height: 70,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), border: Border.all(color: selected ? const Color(0xFF9B63F1) : const Color(0xFFD9D9E8), width: selected ? 2 : 1), boxShadow: const [BoxShadow(color: Color(0x12000000), blurRadius: 8, offset: Offset(0, 3))]),
      child: Stack(children: [
        Positioned.fill(child: Image.network(_images[index], fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: const Color(0xFFE7E5F2)))),
        Positioned.fill(child: ColoredBox(color: Colors.white.withValues(alpha: .78))),
        Center(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(_icons[index], size: 21, color: const Color(0xFF3F3A49)), const SizedBox(width: 8), Text(type, style: TextStyle(color: const Color(0xFF25253E), fontSize: 16, fontWeight: selected ? FontWeight.w700 : FontWeight.w500))])),
        if (selected) const Positioned(right: 8, top: 8, child: Icon(Icons.check_circle, color: Color(0xFF5D2BC1), size: 23)),
      ]),
    ),
  );
  }
}

class _HeroImage extends StatelessWidget {
  const _HeroImage();

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: Stack(children: [
      Positioned.fill(child: Image.network('https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=1200', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF5E617C)))),
      Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: .3))),
    ]),
  );
}

class _CameraAccent extends StatelessWidget {
  const _CameraAccent();

  @override
  Widget build(BuildContext context) => Container(
    width: 155,
    height: 125,
    decoration: BoxDecoration(
      color: const Color(0xFF35264A).withValues(alpha: .9),
      borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(80), topLeft: Radius.circular(80), bottomRight: Radius.circular(18)),
    ),
    child: const Center(child: Icon(Icons.camera_alt_outlined, size: 72, color: Color(0xFFB98DEB))),
  );
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off, size: 44), const SizedBox(height: 12), Text(error.toString(), textAlign: TextAlign.center), const SizedBox(height: 16), OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry'))])));
}

class _ProfileScreen extends StatefulWidget {
  const _ProfileScreen({required this.session, required this.isActive});
  final AuthSession session;
  final bool isActive;

  @override
  State<_ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<_ProfileScreen> {
  final _notifications = NotificationService();
  int? _unreadCount;
  int _countRequest = 0;
  bool _loading = true;
  bool _uploading = false;
  String? _error;
  AuthSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    _initialize();
    _refreshUnreadCount();
  }

  @override
  void didUpdateWidget(covariant _ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) _refreshUnreadCount();
  }

  @override
  void dispose() {
    _notifications.close();
    super.dispose();
  }

  Future<void> _refreshUnreadCount() async {
    final request = ++_countRequest;
    try {
      final count = await _notifications.getUnreadCount();
      if (mounted && request == _countRequest) setState(() => _unreadCount = count);
    } catch (_) {
      // The inbox exposes errors and retry; an unavailable count is not zero.
      if (mounted && request == _countRequest) setState(() => _unreadCount = null);
    }
  }

  Future<void> _openNotifications() async {
    await Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const NotificationsScreen()));
    if (mounted) await _refreshUnreadCount();
  }

  Future<void> _refreshProfileAndNotifications() async {
    await Future.wait([_load(), _refreshUnreadCount()]);
  }

  Future<void> _initialize() async {
    await _load();
    if (!mounted || kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final lost = await ImagePicker().retrieveLostData();
      if (!mounted) return;
      if (lost.exception != null) throw lost.exception!;
      if (lost.files?.isNotEmpty == true) await _upload(lost.files!.first);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to recover your selected photo. Please choose it again.');
    }
  }

  Future<void> _load() async {
    if (_uploading) return;
    setState(() { _loading = true; _error = null; });
    try { await session.refreshProfile(); }
    catch (error) { if (mounted) setState(() => _error = error.toString()); }
    finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => EditProfileScreen(session: session)));
    if (mounted && saved == true) {
      setState(() => _error = null);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile updated.')));
    }
  }

  Future<void> _changePhoto() async {
    setState(() { _uploading = true; _error = null; });
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery, requestFullMetadata: false);
      if (file != null && mounted) await _upload(file);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to open your photo library. Check photo permissions and try again.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _upload(XFile file) async {
    setState(() { _uploading = true; _error = null; });
    try {
      await session.uploadProfilePhoto(file);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile photo updated.')));
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = user?.fullName.trim() ?? '';
    final photo = ApiConfig.imageUrl(user?.profilePhotoUrl);
    final initials = name.split(RegExp(r'\s+')).where((part) => part.isNotEmpty)
        .take(2).map((part) => part.characters.first.toUpperCase()).join();

    Widget menuItem(IconData icon, String title, {String? subtitle, VoidCallback? onTap, int? unreadCount}) {
      final enabled = onTap != null;
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: colors.surface,
          borderRadius: BorderRadius.circular(20),
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            enabled: enabled,
            onTap: onTap,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: enabled ? 0.7 : 0.35),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: enabled ? colors.primary : colors.onSurfaceVariant.withValues(alpha: 0.55)),
            ),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(subtitle ?? 'Not available yet', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              if (unreadCount != null && unreadCount > 0) Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Semantics(label: '$unreadCount unread notifications',
                  child: Badge(label: Text(unreadCount > 99 ? '99+' : '$unreadCount'))),
              ),
              Icon(Icons.chevron_right, color: enabled ? colors.primary : colors.outline),
            ]),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
        child: RefreshIndicator(onRefresh: _refreshProfileAndNotifications, child: ListView(physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(20, 18, 20, 24), children: [
          Row(children: [
            Icon(Icons.camera_alt_outlined, color: colors.primary, size: 22),
            const SizedBox(width: 8),
            Text('SnapSync', style: theme.textTheme.titleMedium?.copyWith(color: colors.primary, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
          ]),
          const SizedBox(height: 16),
          Text('Your profile', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Your details. Your moments. Your SnapSync.',
            style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 18),
          if (_loading || _uploading) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Column(children: [
            Text(_error!, style: TextStyle(color: colors.error), textAlign: TextAlign.center),
            TextButton(onPressed: _loading || _uploading ? null : _load, child: const Text('Refresh profile')),
          ])),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [colors.primaryContainer, colors.surface, colors.primaryContainer.withValues(alpha: 0.45)]),
              border: Border.all(color: colors.primary.withValues(alpha: 0.1)),
              boxShadow: [BoxShadow(color: colors.primary.withValues(alpha: 0.07), blurRadius: 24, offset: const Offset(0, 8))],
            ),
            child: Stack(children: [
              Positioned(right: -22, top: -24, child: ExcludeSemantics(child: Icon(
                Icons.camera_outlined, size: 155, color: colors.primary.withValues(alpha: 0.06)))),
              Padding(padding: const EdgeInsets.all(24), child: Center(child: Column(children: [
                SizedBox(width: 108, height: 108, child: Stack(children: [
                  Container(
                    width: 100, height: 100,
                    decoration: BoxDecoration(shape: BoxShape.circle,
                      border: Border.all(color: colors.surface, width: 4),
                      boxShadow: [BoxShadow(color: colors.primary.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, 4))]),
                    child: ClipOval(child: photo != null ? Image.network(photo, fit: BoxFit.cover,
                      errorBuilder: (_, error, stack) => CircleAvatar(backgroundColor: colors.primaryContainer,
                        child: Text(initials.isEmpty ? '?' : initials, style: TextStyle(color: colors.primary, fontSize: 28)))) : CircleAvatar(backgroundColor: colors.primaryContainer,
                      child: initials.isEmpty
                          ? Icon(Icons.person_outline, size: 42, color: colors.primary)
                          : Text(initials, style: theme.textTheme.headlineMedium?.copyWith(color: colors.primary, fontWeight: FontWeight.w700)))),
                  ),
                  Positioned(right: 0, bottom: 0, child: Tooltip(
                    message: 'Change Photo',
                    child: Container(
                      decoration: BoxDecoration(color: colors.surface, shape: BoxShape.circle,
                        border: Border.all(color: colors.outlineVariant)),
                      child: IconButton(onPressed: _loading || _uploading ? null : _changePhoto, iconSize: 18,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                        icon: const Icon(Icons.camera_alt_outlined)),
                    ),
                  )),
                ])),
                TextButton(onPressed: _loading || _uploading ? null : _changePhoto,
                  child: Text(_uploading ? 'Uploading…' : 'Change Photo')),
                Text('JPEG, PNG or WebP · up to 5 MB', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
                const SizedBox(height: 14),
                Text(name, textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(user?.email ?? '', textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                const SizedBox(height: 16),
                if (user?.phoneNumber?.isNotEmpty == true) Text(user!.phoneNumber!, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 12),
                FilledButton.icon(onPressed: _loading || _uploading ? null : _edit,
                  icon: const Icon(Icons.edit_outlined), label: const Text('Edit Profile')),
              ]))),
            ]),
          ),
          const SizedBox(height: 26),
          Text('Your account', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          menuItem(Icons.auto_awesome, 'Find with AI', subtitle: 'Recommendations and studio approval updates',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AiWorkflowsScreen()))),
          menuItem(Icons.event_note_outlined, 'My Bookings', subtitle: 'View your sessions and booking details',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MyBookingsScreen()))),
          menuItem(Icons.notifications_none_rounded, 'Notifications', subtitle: 'Booking updates and activity',
            onTap: _openNotifications, unreadCount: _unreadCount),
          menuItem(Icons.person_outline_rounded, 'Edit Profile', subtitle: 'Your name and contact details', onTap: _loading || _uploading ? null : _edit),
          menuItem(Icons.settings_outlined, 'Settings', subtitle: 'Appearance and app information',
            onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => const SettingsScreen()))),
          menuItem(Icons.shield_outlined, 'Privacy & Security', subtitle: 'Account details and password',
            onTap: () => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => PrivacySecurityScreen(session: session)))),
          menuItem(Icons.help_outline_rounded, 'Help & Support'),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              try { await session.logout(); }
              catch (_) { if (mounted) setState(() => _error = 'Unable to log out. Please try again.'); }
            },
            style: OutlinedButton.styleFrom(foregroundColor: colors.error,
              side: BorderSide(color: colors.error.withValues(alpha: 0.45)),
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
            icon: const Icon(Icons.logout_rounded), label: const Text('Log out'),
          ),
        ])),
      ))),
    );
  }
}
