import 'package:flutter/material.dart';

import '../services/api_config.dart';

class StudioImage extends StatelessWidget {
  const StudioImage({super.key, this.url, this.profile = false});
  final String? url;
  final bool profile;
  @override
  Widget build(BuildContext context) {
    final resolved = ApiConfig.imageUrl(url);
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Center(
        child: Icon(
          profile ? Icons.camera_alt_outlined : Icons.landscape_outlined,
          size: profile ? 26 : 48,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
    return Semantics(
      label: profile ? 'Studio profile picture' : 'Studio cover photo',
      child: resolved == null
          ? placeholder
          : Image.network(
              resolved,
              fit: BoxFit.cover,
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, error, stack) => placeholder,
              frameBuilder: (_, child, frame, synchronous) =>
                  synchronous || frame != null
                  ? child
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        placeholder,
                        const Center(
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ],
                    ),
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        placeholder,
                        const Center(
                          child: SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ],
                    ),
            ),
    );
  }
}
