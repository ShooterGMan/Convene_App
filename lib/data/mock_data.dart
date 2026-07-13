import '../models/user.dart';
import '../models/meeting.dart';
import '../models/context_thread.dart';
import '../models/group.dart';

// ─── USERS ───────────────────────────────────────────────
class MockUsers {
  static const sarah = AppUser(
    id: 'u1',
    name: 'Sarah Jenkins',
    email: 'sarah@acme.co',
    avatarUrl: 'https://i.pravatar.cc/150?img=47',
    isSelf: true,
  );

  static const alex = AppUser(
    id: 'u2',
    name: 'Alex Chen',
    email: 'alex.c@acme.co',
    avatarUrl: 'https://i.pravatar.cc/150?img=12',
  );

  static const marcus = AppUser(
    id: 'u3',
    name: 'Marcus Johnson',
    email: 'marcus@acme.co',
    avatarUrl: 'https://i.pravatar.cc/150?img=68',
  );

  static const elena = AppUser(
    id: 'u4',
    name: 'Elena Rostova',
    email: 'elena.r@external.com',
  );

  static const priya = AppUser(
    id: 'u5',
    name: 'Priya Sharma',
    email: 'priya@acme.co',
    avatarUrl: 'https://i.pravatar.cc/150?img=45',
  );

  static const james = AppUser(
    id: 'u6',
    name: 'James Wright',
    email: 'james.w@acme.co',
    avatarUrl: 'https://i.pravatar.cc/150?img=53',
  );

  static const all = [sarah, alex, marcus, elena, priya, james];
}

// ─── MEETINGS ────────────────────────────────────────────
class MockMeetings {
  static final today = DateTime.now();

  static final List<Meeting> upcoming = [
    Meeting(
      id: 'm1',
      title: 'Design Sync',
      startTime: DateTime(today.year, today.month, today.day, 10, 0),
      endTime: DateTime(today.year, today.month, today.day, 11, 0),
      type: MeetingType.meet,
      participants: [MockUsers.sarah, MockUsers.alex, MockUsers.marcus, MockUsers.priya, MockUsers.elena],
      groupId: 'g1',
      threadId: 'ct1',
    ),
    Meeting(
      id: 'm2',
      title: 'Weekly Product Review',
      startTime: DateTime(today.year, today.month, today.day, 13, 30),
      endTime: DateTime(today.year, today.month, today.day, 14, 30),
      type: MeetingType.room,
      location: 'Room 4B',
      participants: [MockUsers.sarah, MockUsers.james],
      groupId: 'g2',
    ),
    Meeting(
      id: 'm3',
      title: '1:1 with Alex',
      startTime: DateTime(today.year, today.month, today.day, 16, 0),
      endTime: DateTime(today.year, today.month, today.day, 16, 30),
      type: MeetingType.audio,
      participants: [MockUsers.alex],
    ),
    Meeting(
      id: 'm4',
      title: 'Sprint Planning',
      startTime: DateTime(today.year, today.month, today.day + 1, 9, 0),
      endTime: DateTime(today.year, today.month, today.day + 1, 10, 0),
      type: MeetingType.meet,
      participants: [MockUsers.sarah, MockUsers.alex, MockUsers.marcus, MockUsers.james],
      groupId: 'g1',
    ),
    Meeting(
      id: 'm5',
      title: 'Client Check-in',
      startTime: DateTime(today.year, today.month, today.day + 1, 14, 0),
      endTime: DateTime(today.year, today.month, today.day + 1, 15, 0),
      type: MeetingType.meet,
      participants: [MockUsers.sarah, MockUsers.elena, MockUsers.priya],
      groupId: 'g3',
    ),
  ];
}

// ─── CONTEXT THREADS ─────────────────────────────────────
class MockThreads {
  static final List<ContextThread> threads = [
    ContextThread(
      id: 'ct1',
      meetingTitle: 'Design Sync',
      meetingId: 'm1',
      groupId: 'g1',
      createdAt: DateTime.now().subtract(const Duration(hours: 2)),
      participants: [MockUsers.sarah, MockUsers.alex, MockUsers.marcus, MockUsers.priya],
      vibe: 'Highly Collaborative',
      vibeEmoji: '🚀',
      talkTimeMetrics: {'u1': 0.40, 'u2': 0.30, 'u3': 0.20, 'u5': 0.10},
      blocks: const [
        SmartBlock(
          id: 'sb1',
          type: SmartBlockType.decision,
          content: 'We agreed to migrate to Tailwind v3 across all major repositories by end of Q3.',
          reactions: [
            Reaction(emoji: '👍', count: 4),
            Reaction(emoji: '🚀', count: 2),
          ],
        ),
        SmartBlock(
          id: 'sb2',
          type: SmartBlockType.actionItem,
          content: '@Alex to draft PRD by Friday and share in the main design channel.',
          assignee: 'Alex',
          reactions: [
            Reaction(emoji: '👀', count: 1),
          ],
        ),
        SmartBlock(
          id: 'sb2_sarah',
          type: SmartBlockType.actionItem,
          content: '@Sarah to review the initial mockups before the next sync.',
          assignee: 'Sarah',
        ),
        SmartBlock(
          id: 'sb3',
          type: SmartBlockType.keyInsight,
          content: 'User testing showed a 40% increase in completion rates when we removed the secondary nav on mobile.',
          reactions: [
            Reaction(emoji: '🔥', count: 3),
          ],
        ),
      ],
      isGenerating: false,
    ),
    ContextThread(
      id: 'ct2',
      meetingTitle: 'Backend Architecture Review',
      meetingId: null,
      groupId: 'g1',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      participants: [MockUsers.sarah, MockUsers.marcus, MockUsers.james],
      vibe: 'Technical & Focused',
      vibeEmoji: '⚖️',
      talkTimeMetrics: {'u3': 0.55, 'u6': 0.30, 'u1': 0.15},
      blocks: const [
        SmartBlock(
          id: 'sb4',
          type: SmartBlockType.decision,
          content: '@Marcus proposed moving to microservices architecture. Team agreed to start with the auth service as a pilot.',
          reactions: [
            Reaction(emoji: '✅', count: 3),
          ],
        ),
        SmartBlock(
          id: 'sb5',
          type: SmartBlockType.actionItem,
          content: '@James to set up the new CI/CD pipeline for the auth microservice by next Wednesday.',
          assignee: 'James',
          reactions: [
            Reaction(emoji: '💪', count: 2),
          ],
        ),
        SmartBlock(
          id: 'sb6',
          type: SmartBlockType.keyInsight,
          content: 'Current monolith deployment takes 45 minutes. @Sarah noted that microservices could reduce this to under 5 minutes per service.',
          reactions: [
            Reaction(emoji: '🔥', count: 5),
            Reaction(emoji: '🎯', count: 2),
          ],
        ),
        SmartBlock(
          id: 'sb7',
          type: SmartBlockType.actionItem,
          content: '@Sarah to share the cost analysis for cloud infrastructure scaling with the microservices approach.',
          assignee: 'Sarah',
        ),
      ],
    ),
    ContextThread(
      id: 'ct3',
      meetingTitle: 'Q3 Marketing Strategy',
      groupId: 'g3',
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      participants: [MockUsers.sarah, MockUsers.priya, MockUsers.elena],
      vibe: 'Strategic Planning',
      vibeEmoji: '🎯',
      talkTimeMetrics: {'u5': 0.50, 'u4': 0.40, 'u1': 0.10},
      blocks: const [
        SmartBlock(
          id: 'sb8',
          type: SmartBlockType.decision,
          content: '@Priya confirmed we will focus on three key verticals: healthcare, fintech, and education for Q3 campaigns.',
          reactions: [
            Reaction(emoji: '🎯', count: 3),
          ],
        ),
        SmartBlock(
          id: 'sb9',
          type: SmartBlockType.keyInsight,
          content: 'Elena shared that competitors are investing 60% more in content marketing this quarter. @Elena recommended doubling our blog output.',
          reactions: [
            Reaction(emoji: '📊', count: 2),
          ],
        ),
      ],
    ),
  ];
}

// ─── GROUPS ──────────────────────────────────────────────
class MockGroups {
  static final List<Group> groups = [
    Group(
      id: 'g1',
      name: 'Design Team',
      description: 'Core product design team — weekly syncs and reviews',
      members: [MockUsers.sarah, MockUsers.alex, MockUsers.marcus, MockUsers.james],
      threadIds: ['ct1', 'ct2'],
      createdBy: MockUsers.sarah,
      createdAt: DateTime.now().subtract(const Duration(days: 30)),
      avatarEmoji: '🎨',
    ),
    Group(
      id: 'g2',
      name: 'Product',
      description: 'Cross-functional product development',
      members: [MockUsers.sarah, MockUsers.james, MockUsers.priya],
      threadIds: [],
      createdBy: MockUsers.james,
      createdAt: DateTime.now().subtract(const Duration(days: 14)),
      avatarEmoji: '🚀',
    ),
    Group(
      id: 'g3',
      name: 'Client Relations',
      description: 'External stakeholder meetings and follow-ups',
      members: [MockUsers.sarah, MockUsers.priya, MockUsers.elena],
      threadIds: ['ct3'],
      createdBy: MockUsers.priya,
      createdAt: DateTime.now().subtract(const Duration(days: 7)),
      avatarEmoji: '🤝',
    ),
  ];
}
