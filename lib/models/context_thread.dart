import 'user.dart';

enum SmartBlockType { decision, actionItem, keyInsight }

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

  const SmartBlock({
    required this.id,
    required this.type,
    required this.content,
    this.assignee,
    this.isCompleted = false,
    this.reactions = const [],
  });

  String get typeLabel {
    switch (type) {
      case SmartBlockType.decision:
        return 'Decision';
      case SmartBlockType.actionItem:
        return 'Action Item';
      case SmartBlockType.keyInsight:
        return 'Key Insight';
    }
  }

  SmartBlock copyWith({bool? isCompleted, List<Reaction>? reactions}) {
    return SmartBlock(
      id: id,
      type: type,
      content: content,
      assignee: assignee,
      isCompleted: isCompleted ?? this.isCompleted,
      reactions: reactions ?? this.reactions,
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
      createdAt: DateTime.parse(json['createdAt'] as String),
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
  static SmartBlock fromJson(Map<String, dynamic> json) {
    return SmartBlock(
      id: json['id'] as String,
      type: SmartBlockType.values.firstWhere((e) => e.name == json['type']),
      content: json['content'] as String,
      assignee: json['assignee'] as String?,
      isCompleted: json['isCompleted'] as bool? ?? false,
      reactions: (json['reactions'] as List<dynamic>?)
              ?.map((e) => ReactionJson.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
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
    };
  }
}

extension ThreadCommentJson on ThreadComment {
  static ThreadComment fromJson(Map<String, dynamic> json) {
    return ThreadComment(
      id: json['id'] as String,
      author: AppUser.fromJson(json['author'] as Map<String, dynamic>),
      content: json['content'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
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
