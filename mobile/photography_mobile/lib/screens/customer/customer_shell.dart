import 'package:flutter/material.dart';

import '../../models/studio.dart';
import '../../services/auth_session.dart';
import '../../services/studio_service.dart';
import '../../widgets/studio_card.dart';
import '../studio/studio_detail_screen.dart';
import '../studio/studio_list_screen.dart';

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
      _ProfileScreen(session: widget.session),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
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
    appBar: AppBar(title: const Text('Find your studio')),
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
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                Text('Hello${widget.userName.isEmpty ? '' : ', ${widget.userName.split(' ').first}'}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Let us find the right place for your next story.'),
                const SizedBox(height: 22),
                TextField(controller: _search, onChanged: (_) => setState(() {}), decoration: const InputDecoration(hintText: 'Search studios', prefixIcon: Icon(Icons.search))),
                const SizedBox(height: 18),
                Text('Photography preference', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: _types.map((type) => ChoiceChip(label: Text(type), selected: _type == type, onSelected: (selected) => setState(() => _type = selected ? type : null))).toList()),
                const SizedBox(height: 16),
                TextField(controller: _location, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Location', prefixIcon: Icon(Icons.location_on_outlined))),
                const SizedBox(height: 12),
                Row(children: [Expanded(child: TextField(controller: _minBudget, onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Min budget'))), const SizedBox(width: 12), Expanded(child: TextField(controller: _maxBudget, onChanged: (_) => setState(() {}), keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Max budget')))]),
                const SizedBox(height: 12),
                OutlinedButton.icon(onPressed: _chooseDate, icon: const Icon(Icons.calendar_today_outlined), label: Text(_dateLabel()), style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16))),
                const SizedBox(height: 18),
                FilledButton.icon(onPressed: () => setState(() {}), icon: const Icon(Icons.search), label: const Text('Find studios')),
                const SizedBox(height: 28),
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text('Recommended studios', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)), Text('${studios.length} found')]),
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

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off, size: 44), const SizedBox(height: 12), Text(error.toString(), textAlign: TextAlign.center), const SizedBox(height: 16), OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry'))])));
}

class _ProfileScreen extends StatelessWidget {
  const _ProfileScreen({required this.session});
  final AuthSession session;

  @override
  Widget build(BuildContext context) {
    final user = session.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        CircleAvatar(radius: 34, child: Text(user?.fullName.isNotEmpty == true ? user!.fullName[0].toUpperCase() : '?')),
        const SizedBox(height: 16),
        Center(child: Text(user?.fullName ?? '', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
        Center(child: Text(user?.email ?? '')),
        const SizedBox(height: 28),
        OutlinedButton.icon(onPressed: session.logout, icon: const Icon(Icons.logout), label: const Text('Log out')),
      ]),
    );
  }
}