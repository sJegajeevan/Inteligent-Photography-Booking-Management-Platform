class StudioPortfolioAlbum {
  const StudioPortfolioAlbum({
    required this.id,
    required this.title,
    required this.category,
    this.description = '',
    this.coverImageUrl,
    required this.photoCount,
    this.images = const [],
  });

  final String id, title, category, description;
  final String? coverImageUrl;
  final int photoCount;
  final List<StudioPortfolioImage> images;

  factory StudioPortfolioAlbum.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Missing portfolio album ID');
    }
    String text(String key) => json[key] is String ? json[key] as String : '';
    final images = json['images'] is List
        ? (json['images'] as List)
              .whereType<Map<String, dynamic>>()
              .map(StudioPortfolioImage.fromJson)
              .toList()
        : const <StudioPortfolioImage>[];
    final count = json['photoCount'];
    return StudioPortfolioAlbum(
      id: id,
      title: text('title'),
      category: text('category'),
      description: text('description'),
      coverImageUrl: json['coverImageUrl'] is String
          ? json['coverImageUrl'] as String
          : null,
      photoCount: count is int && count >= 0 ? count : images.length,
      images: images,
    );
  }
}

class StudioPortfolioImage {
  const StudioPortfolioImage({required this.id, required this.imageUrl});

  final String id, imageUrl;

  factory StudioPortfolioImage.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final imageUrl = json['imageUrl'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Missing portfolio image ID');
    }
    if (imageUrl is! String || imageUrl.trim().isEmpty) {
      throw const FormatException('Missing portfolio image URL');
    }
    return StudioPortfolioImage(id: id, imageUrl: imageUrl);
  }
}
