class AccountSession {
  const AccountSession({
    required this.id,
    required this.name,
    required this.databaseName,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String databaseName;
  final DateTime createdAt;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'database_name': databaseName,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory AccountSession.fromMap(Map<String, dynamic> map) {
    return AccountSession(
      id: map['id'] as String,
      name: map['name'] as String,
      databaseName: map['database_name'] as String,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
