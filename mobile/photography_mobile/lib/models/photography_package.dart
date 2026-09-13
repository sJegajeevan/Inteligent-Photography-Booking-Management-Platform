bool isPackageGuid(String value) =>
    RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    ).hasMatch(value) &&
    value.replaceAll('-', '').contains(RegExp(r'[1-9a-fA-F]'));

String _id(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is! String || !isPackageGuid(value)) {
    throw FormatException('Invalid $key');
  }
  return value.toLowerCase();
}

String _text(Map<String, dynamic> json, String key) =>
    json[key] is String ? json[key] as String : '';

double _number(Map<String, dynamic> json, String key, {bool required = false}) {
  final value = json[key];
  if (value == null && !required) return 0;
  if (value is! num || !value.isFinite || value < 0) {
    throw FormatException('Invalid $key');
  }
  return value.toDouble();
}

int _integer(Map<String, dynamic> json, String key) {
  final value = _number(json, key);
  if (value != value.truncateToDouble()) throw FormatException('Invalid $key');
  return value.toInt();
}

List<T> _items<T>(Object? value, T Function(Map<String, dynamic>) parse) {
  if (value == null) return const [];
  if (value is! List) throw const FormatException('Invalid list');
  return List.unmodifiable(
    value.map((item) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid item');
      }
      return parse(item);
    }),
  );
}

DateTime? _date(Map<String, dynamic> json, String key) =>
    DateTime.tryParse(_text(json, key));

String formatLkr(num amount) {
  final parts = amount.toStringAsFixed(2).split('.');
  parts[0] = parts[0].replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]},',
  );
  return 'LKR ${parts.join('.')}';
}

class PackageAddon {
  PackageAddon.fromJson(Map<String, dynamic> json)
    : id = _id(json, 'id'),
      packageId = _id(json, 'packageId'),
      name = _text(json, 'name'),
      description = _text(json, 'description'),
      price = _number(json, 'price', required: true),
      createdAt = _date(json, 'createdAt'),
      updatedAt = _date(json, 'updatedAt');
  final String id, packageId, name, description;
  final double price;
  final DateTime? createdAt, updatedAt;
}

class IncludedPackageService {
  IncludedPackageService.fromJson(Map<String, dynamic> json)
    : id = _id(json, 'id'),
      serviceName = _text(json, 'serviceName'),
      description = _text(json, 'description');
  final String id, serviceName, description;
}

class PhotographyPackage {
  PhotographyPackage.fromJson(Map<String, dynamic> json)
    : id = _id(json, 'id'),
      studioId = _id(json, 'studioId'),
      name = _text(json, 'name'),
      description = _text(json, 'description'),
      basePrice = _number(json, 'basePrice', required: true),
      durationHours = _number(json, 'durationHours'),
      extraHourRate = _number(json, 'extraHourRate'),
      additionalPhotographerRate = _number(json, 'additionalPhotographerRate'),
      numberOfPhotographers = _integer(json, 'numberOfPhotographers'),
      editedPhotoCount = _integer(json, 'editedPhotoCount'),
      albumIncluded = json['albumIncluded'] == true,
      videoIncluded = json['videoIncluded'] == true,
      status = _text(json, 'status'),
      coverImageUrl = _text(json, 'coverImageUrl'),
      createdAt = _date(json, 'createdAt'),
      updatedAt = _date(json, 'updatedAt'),
      services = _items(json['services'], IncludedPackageService.fromJson),
      addons = _items(json['addons'], PackageAddon.fromJson) {
    if (addons.any((addon) => addon.packageId != id)) {
      throw const FormatException('Add-on belongs to a different package');
    }
  }
  final String id, studioId, name, description, status, coverImageUrl;
  final double basePrice,
      durationHours,
      extraHourRate,
      additionalPhotographerRate;
  final int numberOfPhotographers, editedPhotoCount;
  final bool albumIncluded, videoIncluded;
  final DateTime? createdAt, updatedAt;
  final List<IncludedPackageService> services;
  final List<PackageAddon> addons;
  bool get isActive => status.toLowerCase() == 'active';
}

class SelectedPackageAddon {
  SelectedPackageAddon.fromJson(Map<String, dynamic> json)
    : id = _id(json, 'id'),
      name = _text(json, 'name'),
      price = _number(json, 'price', required: true);
  final String id, name;
  final double price;
}

class PackagePriceSummary {
  PackagePriceSummary.fromJson(Map<String, dynamic> json)
    : packageId = _id(json, 'packageId'),
      packageName = _text(json, 'packageName'),
      basePrice = _number(json, 'basePrice', required: true),
      selectedAddons = _items(
        json['selectedAddons'],
        SelectedPackageAddon.fromJson,
      ),
      extraHours = _integer(json, 'extraHours'),
      extraHoursCost = _number(json, 'extraHoursCost', required: true),
      additionalPhotographers = _integer(json, 'additionalPhotographers'),
      additionalPhotographersCost = _number(
        json,
        'additionalPhotographersCost',
        required: true,
      ),
      finalPrice = _number(json, 'finalPrice', required: true);
  final String packageId, packageName;
  final double basePrice,
      extraHoursCost,
      additionalPhotographersCost,
      finalPrice;
  final int extraHours, additionalPhotographers;
  final List<SelectedPackageAddon> selectedAddons;
}

class PackageCustomization {
  PackageCustomization({
    Iterable<String> selectedAddonIds = const [],
    this.extraHours = 0,
    this.additionalPhotographers = 0,
  }) : selectedAddonIds = Set.unmodifiable(selectedAddonIds);
  final Set<String> selectedAddonIds;
  final int extraHours, additionalPhotographers;

  String? validate(PhotographyPackage package) {
    if (!package.isActive) return 'This package is no longer available.';
    if (extraHours < 0 || extraHours > 1000) {
      return 'Extra hours must be between 0 and 1000.';
    }
    if (additionalPhotographers < 0 || additionalPhotographers > 100) {
      return 'Additional photographers must be between 0 and 100.';
    }
    final available = package.addons.map((addon) => addon.id).toSet();
    if (!available.containsAll(selectedAddonIds)) {
      return 'Select only add-ons available for this package.';
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'selectedAddonIds': selectedAddonIds.toList(),
    'extraHours': extraHours,
    'additionalPhotographers': additionalPhotographers,
  };
}
