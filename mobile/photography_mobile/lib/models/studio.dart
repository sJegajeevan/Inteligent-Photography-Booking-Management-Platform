class Studio {
  const Studio({
    required this.id,
    required this.studioName,
    required this.location,
    this.description = '',
    this.descriptionSummary = '',
    this.profileImageUrl,
    this.coverImageUrl,
    this.photographyTypes = const [],
    this.startingPrice,
  });

  final String id, studioName, location, description, descriptionSummary;
  final String? profileImageUrl, coverImageUrl;
  final List<String> photographyTypes;
  final double? startingPrice;

  factory Studio.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Missing studio ID');
    }
    String text(String key) => json[key] is String ? json[key] as String : '';
    final price = json['startingPrice'];
    return Studio(
      id: id,
      studioName: text('studioName'),
      location: text('location'),
      description: text('description'),
      descriptionSummary: text('descriptionSummary'),
      profileImageUrl: json['profileImageUrl'] is String
          ? json['profileImageUrl'] as String
          : null,
      coverImageUrl: json['coverImageUrl'] is String
          ? json['coverImageUrl'] as String
          : null,
      photographyTypes: json['photographyTypes'] is List
          ? (json['photographyTypes'] as List)
                .whereType<String>()
                .where((s) => s.trim().isNotEmpty)
                .toList()
          : const [],
      startingPrice: price is num && price.isFinite && price >= 0
          ? price.toDouble()
          : null,
    );
  }

  bool matches(String query) {
    final terms = _normalizeSearchText(query).split(' ')
      ..removeWhere((term) => term.isEmpty);
    if (terms.isEmpty) return true;

    final searchableText = _normalizeSearchText([
      studioName,
      location,
      description,
      descriptionSummary,
      ...photographyTypes,
    ].join(' '));
    return terms.every(searchableText.contains);
  }

  static String _normalizeSearchText(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String? get priceLabel {
    final price = startingPrice;
    if (price == null) return null;
    final parts = price
        .toStringAsFixed(price == price.roundToDouble() ? 0 : 2)
        .split('.');
    parts[0] = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return 'Starting from LKR ${parts.join('.')}';
  }
}
