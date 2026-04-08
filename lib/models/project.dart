/// Project model — represents a workspace the team works on.
library;

import 'dart:convert';

class Project {
  final String path;
  final String name;
  final DateTime lastOpened;

  const Project({
    required this.path,
    required this.name,
    required this.lastOpened,
  });

  /// Filesystem-safe key derived from the absolute path.
  /// `/Users/dan/MyApp` → `Users-dan-MyApp`
  String get storageKey => path.replaceAll('/', '-').replaceAll(RegExp('^-'), '');

  /// Display name: custom name if set, otherwise the last path segment.
  String get displayName => name.isNotEmpty ? name : path.split('/').last;

  Project copyWith({String? path, String? name, DateTime? lastOpened}) {
    return Project(
      path: path ?? this.path,
      name: name ?? this.name,
      lastOpened: lastOpened ?? this.lastOpened,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'name': name,
        'lastOpened': lastOpened.toIso8601String(),
      };

  factory Project.fromJson(Map<String, dynamic> json) => Project(
        path: json['path'] as String,
        name: json['name'] as String? ?? '',
        lastOpened: DateTime.parse(json['lastOpened'] as String),
      );

  /// Create a project from just a path, using the folder name as display name.
  factory Project.fromPath(String path) => Project(
        path: path,
        name: path.split('/').last,
        lastOpened: DateTime.now(),
      );

  static List<Project> listFromJson(String jsonString) {
    final list = jsonDecode(jsonString) as List;
    return list.map((e) => Project.fromJson(e as Map<String, dynamic>)).toList();
  }

  static String listToJson(List<Project> projects) {
    return jsonEncode(projects.map((p) => p.toJson()).toList());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Project && path == other.path;

  @override
  int get hashCode => path.hashCode;
}
