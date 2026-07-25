import 'package:cloud_firestore/cloud_firestore.dart';
import 'user.dart';

/// A pending invite for a user to join a group, created when an existing
/// member invites someone by email. The invited user must accept or decline
/// before becoming a real member - stored at
/// groups/{groupId}/pendingInvites/{invitedUserId}.
class GroupInvite {
  final String groupId;
  final String groupName;
  final String? groupAvatarEmoji;
  final AppUser invitedBy;
  final String invitedUserId;
  final DateTime invitedAt;

  const GroupInvite({
    required this.groupId,
    required this.groupName,
    this.groupAvatarEmoji,
    required this.invitedBy,
    required this.invitedUserId,
    required this.invitedAt,
  });

  factory GroupInvite.fromJson(Map<String, dynamic> json) {
    return GroupInvite(
      groupId: json['groupId'] as String,
      groupName: json['groupName'] as String? ?? 'Unnamed Group',
      groupAvatarEmoji: json['groupAvatarEmoji'] as String?,
      invitedBy: AppUser.fromJson(json['invitedBy'] as Map<String, dynamic>),
      invitedUserId: json['invitedUserId'] as String,
      invitedAt: json['invitedAt'] is Timestamp
          ? (json['invitedAt'] as Timestamp).toDate()
          : DateTime.parse(json['invitedAt'] as String),
    );
  }
}
