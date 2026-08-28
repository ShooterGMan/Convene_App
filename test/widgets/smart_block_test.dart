import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:convene/models/context_thread.dart';
import 'package:convene/widgets/smart_block.dart';
import 'package:convene/theme/app_theme.dart';

void main() {
  group('SmartBlockWidget Interactive Tests', () {
    Widget buildTestableWidget(Widget child) {
      return MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: child,
          ),
        ),
      );
    }

    testWidgets('renders action item with assignee, priority and due date', (tester) async {
      final block = SmartBlock(
        id: 'block_1',
        type: SmartBlockType.actionItem,
        content: 'Finalize quarterly product roadmap',
        assignee: 'Sarah',
        priority: SmartBlockPriority.high,
        dueDate: DateTime(2026, 8, 30),
        reactions: const [
          Reaction(emoji: '👍', count: 3, isReactedByMe: true),
          Reaction(emoji: '💡', count: 1, isReactedByMe: false),
        ],
      );

      await tester.pumpWidget(buildTestableWidget(
        SmartBlockWidget(block: block),
      ));
      await tester.pumpAndSettle();

      expect(find.text('ACTION ITEM'), findsOneWidget);
      expect(find.text('Finalize quarterly product roadmap'), findsOneWidget);
      expect(find.text('@Sarah'), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget);
      expect(find.text('Due Aug 30'), findsOneWidget);
      expect(find.text('👍'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('💡'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('triggers onToggleComplete callback when checkbox is tapped', (tester) async {
      bool toggleCalled = false;
      final block = SmartBlock(
        id: 'block_2',
        type: SmartBlockType.actionItem,
        content: 'Review marketing copy',
        isCompleted: false,
      );

      await tester.pumpWidget(buildTestableWidget(
        SmartBlockWidget(
          block: block,
          onToggleComplete: () => toggleCalled = true,
        ),
      ));
      await tester.pumpAndSettle();

      // Find the checkbox leading container
      final checkboxFinder = find.byType(GestureDetector).first;
      await tester.tap(checkboxFinder);
      await tester.pumpAndSettle();

      expect(toggleCalled, isTrue);
    });

    testWidgets('triggers onReact callback when reaction pill is tapped', (tester) async {
      String? reactedEmoji;
      final block = SmartBlock(
        id: 'block_3',
        type: SmartBlockType.decision,
        content: 'Launch beta testing next week',
        reactions: const [
          Reaction(emoji: '🔥', count: 4, isReactedByMe: false),
        ],
      );

      await tester.pumpWidget(buildTestableWidget(
        SmartBlockWidget(
          block: block,
          onReact: (emoji) => reactedEmoji = emoji,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('🔥'));
      await tester.pumpAndSettle();

      expect(reactedEmoji, equals('🔥'));
    });

    testWidgets('triggers onAssign callback when Assign chip is tapped', (tester) async {
      bool assignCalled = false;
      final block = SmartBlock(
        id: 'block_4',
        type: SmartBlockType.actionItem,
        content: 'Coordinate design sprint',
      );

      await tester.pumpWidget(buildTestableWidget(
        SmartBlockWidget(
          block: block,
          onAssign: () => assignCalled = true,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Assign'));
      await tester.pumpAndSettle();

      expect(assignCalled, isTrue);
    });
  });
}
