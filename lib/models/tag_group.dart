class TagGroup {
  final int? id;
  final String name;

  TagGroup({
    this.id,
    required this.name,
  });

  factory TagGroup.fromMap(Map<String, dynamic> map) {
    return TagGroup(
      id: map['id'] as int?,
      name: map['name'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
    };
  }

  @override
  String toString() => name;
}
