class StudioServiceItem {
  const StudioServiceItem({
    required this.id,
    required this.serviceName,
    required this.description,
    required this.packageDetails,
    required this.startingPrice,
  });

  final String id, serviceName, description;
  final List<String> packageDetails;
  final double? startingPrice;

  factory StudioServiceItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Missing service ID');
    }
    final price = json['startingPrice'];
    return StudioServiceItem(
      id: id,
      serviceName: json['serviceName'] is String
          ? (json['serviceName'] as String).trim()
          : '',
      description: json['description'] is String
          ? (json['description'] as String).trim()
          : '',
      packageDetails: json['packageDetails'] is List
          ? (json['packageDetails'] as List)
                .whereType<String>()
                .map((detail) => detail.trim())
                .where((detail) => detail.isNotEmpty)
                .toList()
          : const [],
      startingPrice: price is num && price.isFinite && price >= 0
          ? price.toDouble()
          : null,
    );
  }

  String get priceLabel {
    final price = startingPrice;
    if (price == null) return 'Price unavailable';
    final parts = price
        .toStringAsFixed(price == price.roundToDouble() ? 0 : 2)
        .split('.');
    parts[0] = parts[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match[1]},',
    );
    return 'Starting from LKR ${parts.join('.')}';
  }
}
