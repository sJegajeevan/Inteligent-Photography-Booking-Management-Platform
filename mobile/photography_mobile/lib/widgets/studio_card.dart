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
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox.square(
                    dimension: 54,
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
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (studio.location.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  size: 16,
                                  color: Color(0xFF6B7280),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    studio.location,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                      color: const Color(0xFF6B7280),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              if ((detail ? studio.description : studio.descriptionSummary)
                  .isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  detail ? studio.description : studio.descriptionSummary,
                  maxLines: detail ? null : 3,
                  overflow: detail ? null : TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF374151),
                    height: 1.5,
                  ),
                ),
              ],
              if (studio.photographyTypes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3E8FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    studio.priceLabel!,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF6D4AE9),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              if (onView != null) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: onView,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text('View Studio'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
