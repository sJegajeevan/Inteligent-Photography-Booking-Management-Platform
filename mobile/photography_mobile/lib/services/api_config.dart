class ApiConfig {
  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:5284',
  );

  static Uri endpoint(String path) => Uri.parse('$baseUrl/').resolve(path);

  static String? imageUrl(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final text = value.trim();
    if (text.contains('\\') || text.startsWith('//')) return null;
    final uri = Uri.tryParse(text);
    if (uri == null) return null;
    final resolved = uri.hasScheme ? uri : endpoint(text);
    if (!['http', 'https'].contains(resolved.scheme) || resolved.host.isEmpty) {
      return null;
    }
    return resolved.toString();
  }
}
