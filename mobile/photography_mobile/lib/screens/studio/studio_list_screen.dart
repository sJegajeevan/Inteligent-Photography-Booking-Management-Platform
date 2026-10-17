import 'package:flutter/material.dart';

import '../../models/studio.dart';
import '../../services/studio_service.dart';
import '../../services/location_service.dart';
import '../../widgets/studio_card.dart';
import '../../widgets/studio_error.dart';
import 'studio_detail_screen.dart';

class StudioListScreen extends StatefulWidget {
  const StudioListScreen({super.key, this.service, this.locationService});
  final StudioService? service;
  final LocationService? locationService;
  @override
  State<StudioListScreen> createState() => _StudioListScreenState();
}

class _StudioListScreenState extends State<StudioListScreen> {
  late final StudioService _service = widget.service ?? StudioService();
  late Future<List<Studio>> _studios;
  String _query = '';
  bool _findingNearby = false;
  bool _nearby = false;
  int _requestId = 0;
  String? _locationMessage;

  Future<void> _nearMe() async {
    final requestId = ++_requestId;
    setState(() {
      _findingNearby = true;
      _locationMessage = null;
    });
    try {
      final position = await (widget.locationService ?? LocationService())
          .getCurrentLocation();
      if (!mounted || requestId != _requestId) return;
      final studios = await _service.getNearbyStudios(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _nearby = true;
        _studios = Future.value(studios);
      });
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _nearby = false;
        _studios = _service.getStudios();
        _locationMessage =
            error is LocationFailure || error is StudioApiException
            ? error.toString()
            : 'Unable to find nearby studios. You can still browse all studios.';
      });
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _findingNearby = false);
      }
    }
  }

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
    ++_requestId;
    _findingNearby = false;
    _nearby = false;
    _locationMessage = null;
    _studios = _service.getStudios();
  });

  bool _matchesSearch(Studio studio) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return studio.studioName.toLowerCase().contains(query) ||
        studio.location.toLowerCase().contains(query);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Browse Studios')),
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
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilledButton.icon(
                          onPressed: _findingNearby ? null : _nearMe,
                          icon: const Icon(Icons.near_me),
                          label: Text(
                            _findingNearby
                                ? 'Finding nearby studios...'
                                : 'Near Me',
                          ),
                        ),
                        if (_nearby || _findingNearby)
                          TextButton(
                            onPressed: _retry,
                            child: const Text('All studios'),
                          ),
                      ],
                    ),
                    if (_nearby)
                      const Text(
                        'Within 50 km. Nearest first. Straight-line distances.',
                      ),
                    if (_locationMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _locationMessage!,
                          semanticsLabel: _locationMessage,
                        ),
                      ),
                    const SizedBox(height: 20),
                    TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        hintText: 'Search by studio name or location',
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
                      return Center(
                        child: Text(
                          _nearby
                              ? 'No studios within 50 km. Try All studios.'
                              : 'No studios available yet.',
                        ),
                      );
                    }
                    final filtered = studios.where(_matchesSearch).toList();
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
