import 'package:cloud_firestore/cloud_firestore.dart';
import 'user.dart';

enum SmartBlockType { summary, decision, actionItem, keyInsight }

class Reaction {
  final String emoji;
  final int count;
  final bool isReactedByMe;

  const Reaction({
    required this.emoji,
    required this.count,
    this.isReactedByMe = false,
  });

  Reaction copyWith({String? emoji, int? count, bool? isReactedByMe}) {
    return Reaction(
      emoji: emoji ?? this.emoji,
      count: count ?? this.count,
      isReactedByMe: isReactedByMe ?? this.isReactedByMe,
    );
  }
}

class SmartBlock {
  final String id;
  final SmartBlockType type;
  final String content;
  final String? assignee; // For action items — e.g., "@Alex"
  final bool isCompleted; // For action items
  final List<Reaction> reactions;
  // Set when a person corrects the AI's text, so the UI can show an
  // "edited by X" marker instead of silently overwriting the record.
  final String? editedBy;
  final DateTime? editedAt;

  const SmartBlock({
    required this.id,
    required this.type,
    required this.content,
    this.assignee,
    this.isCompleted = false,
    this.reactions = const [],
    this.editedBy,
    this.editedAt,
  });

  String get typeLabel {
    switch (type) {
      case SmartBlockType.summary:
        return 'Summary';
      case SmartBlockType.decision:
        return 'Decision';
      case SmartBlockType.actionItem:
        return 'Action Item';
      case SmartBlockType.keyInsight:
        return 'Key Insight';
    }
  }

  SmartBlock copyWith({
    String? content,
    bool? isCompleted,
    List<Reaction>? reactions,
    String? editedBy,
    DateTime? editedAt,
  }) {
    return SmartBlock(
      id: id,
      type: type,
      content: content ?? this.content,
      assignee: assignee,
      isCompleted: isCompleted ?? this.isCompleted,
      reactions: reactions ?? this.reactions,
      editedBy: editedBy ?? this.editedBy,
      editedAt: editedAt ?? this.editedAt,
    );
  }
}

class ThreadComment {
  final String id;
  final AppUser author;
  final String content;
  final DateTime timestamp;

  const ThreadComment({
    required this.id,
    required this.author,
    required this.content,
    required this.timestamp,
  });
}

class ContextThread {
  final String id;
  final String meetingTitle;
  final String? meetingId;
  final String? groupId;
  final DateTime createdAt;
  final List<AppUser> participants;
  final List<SmartBlock> blocks;
  final List<ThreadComment> comments;
  final bool isGenerating; // AI is still drafting
  
  // Analytics properties
  final String? vibe;
  final String? vibeEmoji;
  final Map<String, double>? talkTimeMetrics;

  const ContextThread({
    required this.id,
    required this.meetingTitle,
    this.meetingId,
    this.groupId,
    required this.createdAt,
    required this.participants,
    required this.blocks,
    this.comments = const [],
    this.isGenerating = false,
    this.vibe,
    this.vibeEmoji,
    this.talkTimeMetrics,
  });

  factory ContextThread.fromJson(Map<String, dynamic> json) {
    return ContextThread(
      id: json['id'] as String,
      meetingTitle: json['meetingTitle'] as String,
      meetingId: json['meetingId'] as String?,
      groupId: json['groupId'] as String?,
      createdAt: json['createdAt'] is Timestamp 
          ? (json['createdAt'] as Timestamp).toDate() 
          : DateTime.parse(json['createdAt'] as String),
      participants: (json['participants'] as List<dynamic>?)
              ?.map((e) => AppUser.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      blocks: (json['blocks'] as List<dynamic>?)
              ?.map((e) => SmartBlockJson.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      comments: (json['comments'] as List<dynamic>?)
              ?.map((e) => ThreadCommentJson.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      isGenerating: json['isGenerating'] as bool? ?? false,
      vibe: json['vibe'] as String?,
      vibeEmoji: json['vibeEmoji'] as String?,
      talkTimeMetrics: (json['talkTimeMetrics'] as Map<String, dynamic>?)?.map(
        (k, e) => MapEntry(k, (e as num).toDouble()),
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'meetingTitle': meetingTitle,
      'meetingId': meetingId,
      'groupId': groupId,
      'createdAt': createdAt.toIso8601String(),
      'participants': participants.map((e) => e.toJson()).toList(),
      // Flat list of participant UIDs, kept in sync with `participants` -
      // Firestore security rules key off this to check thread access.
      'participantIds': participants.map((e) => e.id).toList(),
      'blocks': blocks.map((e) => e.toJson()).toList(),
      'comments': comments.map((e) => e.toJson()).toList(),
      'isGenerating': isGenerating,
      'vibe': vibe,
      'vibeEmoji': vibeEmoji,
      'talkTimeMetrics': talkTimeMetrics,
    };
  }
}

extension ReactionJson on Reaction {
  static Reaction fromJson(Map<String, dynamic> json) {
    return Reaction(
      emoji: json['emoji'] as String,
      count: json['count'] as int,
      isReactedByMe: json['isReactedByMe'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'emoji': emoji,
      'count': count,
      'isReactedByMe': isReactedByMe,
    };
  }
}

extension SmartBlockJson on SmartBlock {
  static SmartBlockType _parseType(String? t) {
    if (t == null) return SmartBlockType.keyInsight;
    final lower = t.toLowerCase();
    if (lower.contains('summary')) return SmartBlockType.summary;
    if (lower.contains('decision')) return SmartBlockType.decision;
    if (lower.contains('action')) return SmartBlockType.actionItem;
    return SmartBlockType.keyInsight;
  }

  static SmartBlock fromJson(Map<String, dynamic> json) {
    return SmartBlock(
      id: json['id'] as String? ?? 'block_${DateTime.now().millisecondsSinceEpoch}_${json.hashCode}',
      type: _parseType(json['type'] as String?),
      content: json['content'] as String? ?? '',
      assignee: json['assignee'] as String?,
      isCompleted: json['isCompleted'] as bool? ?? false,
      reactions: (json['reactions'] as List<dynamic>?)
              ?.map((e) => ReactionJson.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      editedBy: json['editedBy'] as String?,
      editedAt: json['editedAt'] == null
          ? null
          : (json['editedAt'] is Timestamp
              ? (json['editedAt'] as Timestamp).toDate()
              : DateTime.tryParse(json['editedAt'] as String)),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type.name,
      'content': content,
      'assignee': assignee,
      'isCompleted': isCompleted,
      'reactions': reactions.map((e) => e.toJson()).toList(),
      'editedBy': editedBy,
      'editedAt': editedAt?.toIso8601String(),
    };
  }
}

extension ThreadCommentJson on ThreadComment {
  static ThreadComment fromJson(Map<String, dynamic> json) {
    return ThreadComment(
      id: json['id'] as String,
      author: AppUser.fromJson(json['author'] as Map<String, dynamic>),
      content: json['content'] as String,
      timestamp: json['timestamp'] is Timestamp
          ? (json['timestamp'] as Timestamp).toDate()
          : DateTime.parse(json['timestamp'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'author': author.toJson(),
      'content': content,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
