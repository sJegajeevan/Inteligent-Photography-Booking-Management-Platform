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
    appBar: AppBar(title: const Text('Studios')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Find the perfect studio for your special moments',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        hintText: 'Search studios...',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ],
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
