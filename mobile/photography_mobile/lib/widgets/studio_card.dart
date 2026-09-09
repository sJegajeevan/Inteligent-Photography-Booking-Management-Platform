import 'package:flutter/material.dart';

import '../models/studio.dart';
import 'studio_image.dart';

class StudioCard extends StatelessWidget {
  const StudioCard({
    super.key,
    required this.studio,
    this.onView,
    this.detail = false,
  });
  final Studio studio;
  final VoidCallback? onView;
  final bool detail;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 20),
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: StudioImage(url: studio.coverImageUrl),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox.square(
                    dimension: 56,
                    child: ClipOval(
                      child: StudioImage(
                        url: studio.profileImageUrl,
                        profile: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          studio.studioName,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        if (studio.location.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              studio.location,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if ((detail ? studio.description : studio.descriptionSummary)
                  .isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  detail ? studio.description : studio.descriptionSummary,
                  maxLines: detail ? null : 3,
                  overflow: detail ? null : TextOverflow.ellipsis,
                ),
              ],
              if (studio.photographyTypes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: studio.photographyTypes
                      .map(
                        (type) => Chip(
                          label: Text(type),
                          visualDensity: VisualDensity.compact,
                        ),
                      )
                      .toList(),
                ),
              ],
              if (studio.priceLabel != null) ...[
                const SizedBox(height: 16),
                Text(
                  studio.priceLabel!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (onView != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: onView,
                    label: const Text('View Studio'),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}
