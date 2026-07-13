import 'user.dart';
class Group {
  final String id;
  final String name;
  final String? description;
  final List<AppUser> members;
  final List<String> threadIds; // References to ContextThread IDs
  final AppUser createdBy;
  final DateTime createdAt;
  final String? avatarEmoji; // Emoji as group icon

  const Group({
    required this.id,
    required this.name,
    this.description,
    required this.members,
    this.threadIds = const [],
    required this.createdBy,
    required this.createdAt,
    this.avatarEmoji,
  });

  factory Group.fromJson(Map<String, dynamic> json) {
    return Group(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      members: (json['members'] as List<dynamic>?)
              ?.map((e) => AppUser.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      threadIds: (json['threadIds'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      createdBy: AppUser.fromJson(json['createdBy'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['createdAt'] as String),
      avatarEmoji: json['avatarEmoji'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'members': members.map((e) => e.toJson()).toList(),
      'threadIds': threadIds,
      'createdBy': createdBy.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'avatarEmoji': avatarEmoji,
    };
  }

  int get memberCount => members.length;
}
