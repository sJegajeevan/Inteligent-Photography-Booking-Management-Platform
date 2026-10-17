import 'package:flutter/material.dart';

import '../../models/studio.dart';
import '../../models/studio_portfolio.dart';
import '../../services/api_config.dart';
import '../../services/studio_service.dart';
import '../../widgets/studio_availability_tab.dart';
import '../../widgets/studio_card.dart';
import '../../widgets/studio_error.dart';
import '../../widgets/studio_image.dart';
import '../../widgets/studio_packages_section.dart';
import '../../widgets/studio_services_tab.dart';

class StudioDetailScreen extends StatefulWidget {
  const StudioDetailScreen({super.key, required this.studioId, this.service});
  final String studioId;
  final StudioService? service;
  @override
  State<StudioDetailScreen> createState() => _StudioDetailScreenState();
}

class _StudioDetailScreenState extends State<StudioDetailScreen> {
  late final StudioService _service = widget.service ?? StudioService();
  late Future<Studio> _studio;
  @override
  void initState() {
    super.initState();
    _studio = _service.getStudio(widget.studioId);
  }

  @override
  void dispose() {
    if (widget.service == null) _service.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Studio details')),
    body: SafeArea(
      child: FutureBuilder<Studio>(
        future: _studio,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return StudioError(
              error: snapshot.error!,
              onRetry: () => setState(() {
                _studio = _service.getStudio(widget.studioId);
              }),
            );
          }
          final studio = snapshot.data!;
          return DefaultTabController(
            length: 5,
            child: Column(
              children: [
                Material(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  child: const TabBar(
                    isScrollable: true,
                    tabs: [
                      Tab(text: 'Overview'),
                      Tab(text: 'Portfolio'),
                      Tab(text: 'Services'),
                      Tab(text: 'Availability'),
                      Tab(text: 'Packages'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _OverviewTab(studio: studio),
                      _PortfolioTab(
                        key: ValueKey('portfolio-${studio.id}'),
                        studioId: studio.id,
                        service: _service,
                      ),
                      StudioServicesTab(
                        key: ValueKey('services-${widget.studioId}'),
                        studioId: widget.studioId,
                        service: _service,
                      ),
                      StudioAvailabilityTab(
                        key: ValueKey('availability-${widget.studioId}'),
                        studioId: widget.studioId,
                        service: _service,
                      ),
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: StudioPackagesSection(
                              key: ValueKey('packages-${widget.studioId}'),
                              studioId: widget.studioId,
                              studioName: studio.studioName,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.studio});
  final Studio studio;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [StudioCard(studio: studio, detail: true)],
      ),
    ),
  );
}

class _PortfolioTab extends StatefulWidget {
  const _PortfolioTab({super.key, required this.studioId, required this.service});
  final String studioId;
  final StudioService service;

  @override
  State<_PortfolioTab> createState() => _PortfolioTabState();
}

class _PortfolioTabState extends State<_PortfolioTab> {
  late Future<List<StudioPortfolioAlbum>> _albums;
  StudioPortfolioAlbum? _selectedAlbum;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PortfolioTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studioId != widget.studioId) {
      _selectedAlbum = null;
      _load();
    }
  }

  void _load() {
    _albums = widget.service.getPortfolio(widget.studioId);
  }

  void _retry() => setState(_load);

  @override
  Widget build(BuildContext context) => FutureBuilder<List<StudioPortfolioAlbum>>(
    future: _albums,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError) {
        return StudioError(error: snapshot.error!, onRetry: _retry);
      }
      final albums = snapshot.data ?? const <StudioPortfolioAlbum>[];
      if (_selectedAlbum != null) {
        return _AlbumGallery(
          album: _selectedAlbum!,
          onBack: () => setState(() => _selectedAlbum = null),
        );
      }
      if (albums.isEmpty) {
        return const Center(child: Text('No portfolio albums available yet.'));
      }
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: GridView.builder(
            padding: const EdgeInsets.all(20),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 340,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: .84,
            ),
            itemCount: albums.length,
            itemBuilder: (context, index) => _PortfolioAlbumCard(
              album: albums[index],
              onTap: () => setState(() => _selectedAlbum = albums[index]),
            ),
          ),
        ),
      );
    },
  );
}

class _PortfolioAlbumCard extends StatelessWidget {
  const _PortfolioAlbumCard({required this.album, required this.onTap});
  final StudioPortfolioAlbum album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: StudioImage(url: album.coverImageUrl)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (album.category.isNotEmpty)
                  Text(
                    album.category,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  album.title.isEmpty ? 'Untitled album' : album.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${album.photoCount} ${album.photoCount == 1 ? 'photo' : 'photos'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _AlbumGallery extends StatelessWidget {
  const _AlbumGallery({required this.album, required this.onBack});
  final StudioPortfolioAlbum album;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
              label: const Text('All albums'),
            ),
          ),
          Text(
            album.title.isEmpty ? 'Untitled album' : album.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (album.category.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(album.category),
          ],
          const SizedBox(height: 16),
          if (album.images.isEmpty)
            const Text('No photos are available for this album.')
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 180,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: album.images.length,
              itemBuilder: (context, index) => _GalleryThumb(
                image: album.images[index],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _PhotoViewer(
                      imageUrl: album.images[index].imageUrl,
                      title: album.title,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

class _GalleryThumb extends StatelessWidget {
  const _GalleryThumb({
    required this.image,
    required this.onTap,
  });
  final StudioPortfolioImage image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Material(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: InkWell(
        onTap: onTap,
        child: StudioImage(url: image.imageUrl),
      ),
    ),
  );
}

class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.imageUrl, required this.title});
  final String imageUrl, title;

  @override
  Widget build(BuildContext context) {
    final resolved = ApiConfig.imageUrl(imageUrl);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: Colors.black,
        title: Text(title.isEmpty ? 'Portfolio photo' : title),
      ),
      body: Center(
        child: resolved == null
            ? const Icon(Icons.broken_image_outlined, color: Colors.white, size: 48)
            : InteractiveViewer(
                child: Image.network(
                  resolved,
                  fit: BoxFit.contain,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (_, error, stack) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
      ),
    );
  }
}
