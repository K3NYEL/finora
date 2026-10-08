class AppUser {
  const AppUser({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.createdAt,
    this.lastLogin,
  });

  final String id;
  final String firstName;
  final String lastName;
  final DateTime createdAt;
  final DateTime? lastLogin;

  String get fullName => '$firstName $lastName';

  factory AppUser.fromMap(Map<String, Object?> map) {
    return AppUser(
      id: map['id'] as String,
      firstName: map['first_name'] as String,
      lastName: map['last_name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      lastLogin: map['last_login'] == null
          ? null
          : DateTime.parse(map['last_login'] as String),
    );
  }
}
