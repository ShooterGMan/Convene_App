import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'user.dart';

/// Generates a short, hard-to-guess invite code for shareable group links.
String generateInviteCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no ambiguous chars (0/O, 1/I)
  final rand = Random.secure();
  return List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
}

class Group {
  final String id;
  final String name;
  final String? description;
  final List<AppUser> members;
  final Map<String, DateTime> memberJoinedAt; // uid -> when they joined, for "New" badges
  final List<String> threadIds; // References to ContextThread IDs
  final AppUser createdBy;
  final DateTime createdAt;
  final String? avatarEmoji; // Emoji as group icon
  final String inviteCode; // Shareable link code to join this group
  final List<String> adminIds; // uids that can manage the group (delete, edit, promote/remove)

  const Group({
    required this.id,
    required this.name,
    this.description,
    required this.members,
    this.memberJoinedAt = const {},
    this.threadIds = const [],
    required this.createdBy,
    required this.createdAt,
    this.avatarEmoji,
    this.inviteCode = '',
    this.adminIds = const [],
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
      memberJoinedAt: (json['memberJoinedAt'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(
            k,
            v is Timestamp ? v.toDate() : DateTime.parse(v as String),
          )) ??
          {},
      threadIds: (json['threadIds'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
      createdBy: AppUser.fromJson(json['createdBy'] as Map<String, dynamic>),
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.parse(json['createdAt'] as String),
      avatarEmoji: json['avatarEmoji'] as String?,
      inviteCode: json['inviteCode'] as String? ?? '',
      adminIds: (json['adminIds'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'members': members.map((e) => e.toJson()).toList(),
      // Flat list of member UIDs, kept in sync with `members` - Firestore
      // security rules key off this to check group membership.
      'memberIds': members.map((e) => e.id).toList(),
      'memberJoinedAt': memberJoinedAt.map((k, v) => MapEntry(k, v.toIso8601String())),
      'threadIds': threadIds,
      'createdBy': createdBy.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'avatarEmoji': avatarEmoji,
      'inviteCode': inviteCode,
      'adminIds': adminIds.isEmpty ? [createdBy.id] : adminIds,
    };
  }

  int get memberCount => members.length;

  /// Whether this member joined recently enough to show a "New" badge.
  bool isRecentMember(String userId) {
    final joinedAt = memberJoinedAt[userId];
    if (joinedAt == null) return false;
    return DateTime.now().difference(joinedAt).inDays < 7;
  }

  /// Effective admin set. Older groups created before multi-admin support
  /// have no `adminIds` - the original creator is the implicit admin.
  List<String> get effectiveAdminIds => adminIds.isNotEmpty ? adminIds : [createdBy.id];

  bool isAdmin(String userId) => effectiveAdminIds.contains(userId);
}
