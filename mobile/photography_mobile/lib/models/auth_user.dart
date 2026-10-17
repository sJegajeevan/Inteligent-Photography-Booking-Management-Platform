class AuthUser {
  const AuthUser({required this.id, required this.fullName, required this.email, required this.role, this.phoneNumber, this.profilePhotoUrl});

  final int id;
  final String fullName;
  final String email;
  final String role;
  final String? phoneNumber;
  final String? profilePhotoUrl;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! int) throw const FormatException('Missing user ID');
    return AuthUser(
      id: id,
      fullName: json['fullName'] is String ? json['fullName'] as String : '',
      email: json['email'] is String ? json['email'] as String : '',
      role: json['role'] is String ? json['role'] as String : '',
      phoneNumber: json['phoneNumber'] as String?,
      profilePhotoUrl: json['profilePhotoUrl'] as String?,
    );
  }
}
