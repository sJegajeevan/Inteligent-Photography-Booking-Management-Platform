import 'package:flutter/material.dart';

import '../services/api_config.dart';

class StudioImage extends StatelessWidget {
  const StudioImage({super.key, this.url, this.profile = false});
  final String? url;
  final bool profile;

  @override
  Widget build(BuildContext context) {
    final resolved = ApiConfig.imageUrl(url);
    final colorScheme = Theme.of(context).colorScheme;

    Widget placeholder({bool failed = false}) => ColoredBox(
      color: colorScheme.primaryContainer.withValues(alpha: 0.55),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              failed
                  ? Icons.image_not_supported_outlined
                  : profile
                  ? Icons.camera_alt_outlined
                  : Icons.landscape_outlined,
              size: profile ? 26 : 42,
              color: colorScheme.primary,
            ),
            if (!profile) ...[
              const SizedBox(height: 6),
              Text(
                failed ? 'Image unavailable' : 'No photo yet',
                style: Theme.of(context).textTheme.labelMedium
                    ?.copyWith(color: colorScheme.onPrimaryContainer),
              ),
            ],
          ],
        ),
      ),
    );

    return Semantics(
      image: true,
      excludeSemantics: true,
      label: profile
          ? 'Studio profile photo'
          : 'Studio cover photo${resolved == null ? ', not provided' : ''}',
      child: resolved == null
          ? placeholder()
          : Image.network(
              resolved,
              fit: BoxFit.cover,
              webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (_, error, stack) => placeholder(failed: true),
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        placeholder(),
                        Center(
                          child: SizedBox(
                            width: 36,
                            child: LinearProgressIndicator(
                              value:
                                  progress.expectedTotalBytes == null ||
                                      progress.expectedTotalBytes! <= 0
                                  ? null
                                  : (progress.cumulativeBytesLoaded /
                                            progress.expectedTotalBytes!)
                                        .clamp(0.0, 1.0),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
    );
  }
}
