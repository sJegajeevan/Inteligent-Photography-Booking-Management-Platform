import 'package:flutter/material.dart';

import '../../models/studio.dart';
import '../../services/studio_service.dart';
import '../../widgets/studio_card.dart';
import '../../widgets/studio_empty_state.dart';
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
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String? _selectedType;

  @override
  void initState() {
    super.initState();
    _studios = _service.getStudios();
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (widget.service == null) _service.close();
    super.dispose();
  }

  void _retry() => setState(() {
    _studios = _service.getStudios();
  });

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _query = '';
      _selectedType = null;
    });
  }

  bool _matchesType(Studio studio) {
    final selectedType = _selectedType;
    return selectedType == null ||
        studio.photographyTypes.any(
          (type) => type.toLowerCase() == selectedType.toLowerCase(),
        );
  }

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
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
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
                        color: Theme.of(context).colorScheme.primary
                            .withValues(alpha: 0.22),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Find your perfect photography studio',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Browse photographers for weddings, portraits and events.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.94),
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Semantics(
                        label: 'Search studios by name, location, description or photography type',
                        textField: true,
                        child: TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          onChanged: (value) => setState(() => _query = value),
                          decoration: InputDecoration(
                            hintText: 'Name, location or photography type',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'Clear search',
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _query = '');
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
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
                      return Center(
                        child: Semantics(
                          label: 'Loading studios',
                          child: const CircularProgressIndicator(),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return StudioError(
                        error: snapshot.error!,
                        onRetry: _retry,
                      );
                    }

                    final studios = snapshot.data!;
                    if (studios.isEmpty) {
                      return const StudioEmptyState(
                        title: 'No studios available yet.',
                        message: 'New studios will appear here when photographers publish their profiles.',
                      );
                    }

                    final types =
                        studios
                            .expand((studio) => studio.photographyTypes)
                            .map((type) => type.trim())
                            .where((type) => type.isNotEmpty)
                            .toSet()
                            .toList()
                          ..sort(
                            (a, b) =>
                                a.toLowerCase().compareTo(b.toLowerCase()),
                          );
                    final filtered = studios
                        .where((studio) => studio.matches(_query))
                        .where(_matchesType)
                        .toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (types.isNotEmpty)
                          SizedBox(
                            height: 48,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Semantics(
                                    label: 'Show all photography types',
                                    selected: _selectedType == null,
                                    child: ChoiceChip(
                                      label: const Text('All types'),
                                      selected: _selectedType == null,
                                      onSelected: (_) =>
                                          setState(() => _selectedType = null),
                                    ),
                                  ),
                                ),
                                for (final type in types)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Semantics(
                                      label: 'Filter studios by $type',
                                      selected:
                                          _selectedType?.toLowerCase() ==
                                          type.toLowerCase(),
                                      child: ChoiceChip(
                                        label: Text(type),
                                        selected:
                                            _selectedType?.toLowerCase() ==
                                            type.toLowerCase(),
                                        onSelected: (selected) => setState(
                                          () => _selectedType = selected
                                              ? type
                                              : null,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              '${filtered.length} ${filtered.length == 1 ? 'studio' : 'studios'} found',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: filtered.isEmpty
                              ? StudioEmptyState(
                                  title: 'No studios match your search.',
                                  message: 'Try another name or location, or clear your search and filters.',
                                  actionLabel: 'Clear search and filters',
                                  onAction: _clearFilters,
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    0,
                                    20,
                                    20,
                                  ),
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
                                ),
                        ),
                      ],
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
