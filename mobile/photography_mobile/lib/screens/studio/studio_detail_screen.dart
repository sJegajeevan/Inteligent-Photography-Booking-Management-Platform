import 'package:flutter/material.dart';

import '../../models/studio.dart';
import '../../services/studio_service.dart';
import '../../widgets/studio_card.dart';
import '../../widgets/studio_error.dart';

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
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  StudioCard(studio: snapshot.data!, detail: true),
                  // Future sections can use /{studioId}/portfolio, /services and /availability.
                  // Keep these independent of the overview request when implemented.
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
