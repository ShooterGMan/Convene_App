import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../models/context_thread.dart';
import '../theme/app_theme.dart';

class ReactionBar extends StatefulWidget {
  final List<Reaction> reactions;
  final ValueChanged<int>? onReactionTap;

  const ReactionBar({
    super.key,
    required this.reactions,
    this.onReactionTap,
  });

  @override
  State<ReactionBar> createState() => _ReactionBarState();
}

class _ReactionBarState extends State<ReactionBar> {
  int? _tappedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.reactions.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ...widget.reactions.asMap().entries.map((entry) {
          final index = entry.key;
          final reaction = entry.value;
          return _ReactionPill(
            reaction: reaction,
            isBouncing: _tappedIndex == index,
            onTap: () {
              setState(() => _tappedIndex = index);
              widget.onReactionTap?.call(index);
              // Reset bounce after animation
              Future.delayed(300.ms, () {
                if (mounted) setState(() => _tappedIndex = null);
              });
            },
          );
        }),
        // Add reaction button
        GestureDetector(
          onTap: () {
            // Placeholder for add reaction flow
          },
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.colors.background,
              shape: BoxShape.circle,
              border: Border.all(color: context.colors.border, width: 1),
            ),
            child: Icon(
              Icons.add,
              size: 18,
              color: context.colors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _ReactionPill extends StatelessWidget {
  final Reaction reaction;
  final bool isBouncing;
  final VoidCallback onTap;

  const _ReactionPill({
    required this.reaction,
    required this.isBouncing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pill = GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: 200.ms,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: reaction.isReactedByMe
              ? context.colors.primaryLight
              : context.colors.background,
          borderRadius: BorderRadius.circular(AppRadius.full),
          border: Border.all(
            color: reaction.isReactedByMe
                ? context.colors.primary.withValues(alpha: 0.3)
                : context.colors.border,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              reaction.emoji,
              style: TextStyle(fontSize: 16),
            ),
            SizedBox(width: 6),
            Text(
              '${reaction.count}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: reaction.isReactedByMe
                        ? context.colors.primary
                        : context.colors.textMuted,
                    fontSize: 13,
                  ),
            ),
          ],
        ),
      ),
    );

    if (isBouncing) {
      return pill
          .animate(onPlay: (controller) => controller.forward())
          .scale(
            begin: const Offset(1.0, 1.0),
            end: const Offset(1.2, 1.2),
            duration: 150.ms,
            curve: Curves.easeOut,
          )
          .then()
          .scale(
            begin: const Offset(1.2, 1.2),
            end: const Offset(1.0, 1.0),
            duration: 150.ms,
            curve: Curves.elasticOut,
          );
    }

    return pill;
  }
}
