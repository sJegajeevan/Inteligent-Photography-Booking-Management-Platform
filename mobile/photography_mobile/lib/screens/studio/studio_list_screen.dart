import 'package:flutter/material.dart';

import '../../models/studio.dart';
import '../../services/studio_service.dart';
import '../../widgets/studio_card.dart';
import '../../widgets/studio_error.dart';
import 'studio_detail_screen.dart';

class StudioListScreen extends StatefulWidget {
  const StudioListScreen({super.key, this.service});
  final StudioService? service;
  @override
  State<StudioListScreen> createState() => _StudioListScreenState();
}

class _StudioListScreenState extends State<StudioListScreen> {
  late final StudioService _service = widget.service ?? StudioService();
  late Future<List<Studio>> _studios;
  String _query = '';
  @override
  void initState() {
    super.initState();
    _studios = _service.getStudios();
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  void _retry() => setState(() {
    _studios = _service.getStudios();
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Studios'),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: IconButton(
            onPressed: _retry,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh studios',
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.secondary,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                        blurRadius: 22,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Find your perfect photography studio',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Browse trusted photographers for weddings, portraits and events.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        onChanged: (value) => setState(() => _query = value),
                        decoration: InputDecoration(
                          hintText: 'Search by studio, location or type',
                          prefixIcon: const Icon(Icons.search_rounded),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: 0.95),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: FutureBuilder<List<Studio>>(
                  future: _studios,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return StudioError(
                        error: snapshot.error!,
                        onRetry: _retry,
                      );
                    }
                    final studios = snapshot.data!;
                    if (studios.isEmpty) {
                      return const Center(
                        child: Text('No studios available yet.'),
                      );
                    }
                    final filtered = studios
                        .where((studio) => studio.matches(_query))
                        .toList();
                    if (filtered.isEmpty) {
                      return const Center(
                        child: Text('No studios match your search.'),
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final studio = filtered[index];
                        return StudioCard(
                          studio: studio,
                          onView: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => StudioDetailScreen(
                                studioId: studio.id,
                                service: _service,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
