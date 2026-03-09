import 'package:flutter/material.dart';
enum TagType { expense, income }

extension TagTypeExtension on TagType {
  String get name => toString().split('.').last;
  Color get color => this == TagType.income ? Colors.green : Colors.red;
  IconData get icon => this == TagType.income ? Icons.arrow_upward : Icons.arrow_downward;
}

class Tag {
  final int? id;
  final String name;
  final TagType type;

  Tag({
    this.id,
    required this.name,
    required this.type,
  });

  factory Tag.fromMap(Map<String, dynamic> map) {
    return Tag(
      id: map['id'] as int?,
      name: map['name'] as String,
      type: TagType.values.byName(map['type'] as String),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
    };
  }

  @override
  String toString() => '$name (${type.name})';
}