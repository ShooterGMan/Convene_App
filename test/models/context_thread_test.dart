import 'package:flutter_test/flutter_test.dart';
import 'package:convene/models/context_thread.dart';
import 'package:convene/models/user.dart';

void main() {
  group('ContextThread & SmartBlock Model Tests', () {
    final sampleUser = AppUser(id: 'u1', name: 'Alice Smith', email: 'alice@example.com');

    test('Reaction model and copyWith', () {
      final reaction = Reaction(
        emoji: '👍',
        count: 3,
        isReactedByMe: false,
      );

      expect(reaction.emoji, '👍');
      expect(reaction.count, 3);
      expect(reaction.isReactedByMe, false);

      final updated = reaction.copyWith(count: 4, isReactedByMe: true);
      expect(updated.count, 4);
      expect(updated.isReactedByMe, true);
    });

    test('SmartBlock serialization and typeLabel', () {
      final block = SmartBlock(
        id: 'b1',
        type: SmartBlockType.actionItem,
        content: 'Finalize Q3 roadmap document',
        assignee: 'Alice',
        assignedUserId: 'u1',
        priority: SmartBlockPriority.high,
        dueDate: DateTime(2026, 9, 1),
        isCompleted: false,
        reactions: [
          Reaction(emoji: '🔥', count: 2, isReactedByMe: true),
        ],
      );

      expect(block.id, 'b1');
      expect(block.typeLabel, 'Action Item');
      expect(block.assignee, 'Alice');
      expect(block.priority, SmartBlockPriority.high);

      final updated = block.copyWith(isCompleted: true);
      expect(updated.isCompleted, true);
      expect(updated.content, block.content);
    });

    test('ContextThread full model serialization', () {
      final thread = ContextThread(
        id: 'th_123',
        meetingTitle: 'Design Alignment',
        createdAt: DateTime(2026, 8, 20, 14, 0),
        vibe: 'Collaborative & Energetic',
        vibeEmoji: '✨',
        participants: [sampleUser],
        blocks: [
          SmartBlock(
            id: 'sb1',
            type: SmartBlockType.summary,
            content: 'Team aligned on mobile-first navigation overhaul.',
          ),
          SmartBlock(
            id: 'sb2',
            type: SmartBlockType.decision,
            content: 'Adopt standard bottom sheet patterns for actions.',
          ),
        ],
      );

      final json = thread.toJson();
      expect(json['id'], 'th_123');
      expect(json['meetingTitle'], 'Design Alignment');
      expect(json['vibe'], 'Collaborative & Energetic');
      expect(json['vibeEmoji'], '✨');
      expect(json['participantIds'], ['u1']);

      final fromJson = ContextThread.fromJson(json);
      expect(fromJson.id, thread.id);
      expect(fromJson.meetingTitle, thread.meetingTitle);
      expect(fromJson.blocks.length, 2);
      expect(fromJson.blocks[0].type, SmartBlockType.summary);
      expect(fromJson.blocks[1].type, SmartBlockType.decision);
      expect(fromJson.vibe, 'Collaborative & Energetic');
    });
  });
}
