import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import '../models/context_thread.dart';
import '../theme/app_theme.dart';

class SmartBlockWidget extends StatelessWidget {
  final SmartBlock block;
  final VoidCallback? onToggleComplete;
  final VoidCallback? onReact;
  final VoidCallback? onEdit;
  final VoidCallback? onAssign;

  const SmartBlockWidget({
    super.key,
    required this.block,
    this.onToggleComplete,
    this.onReact,
    this.onEdit,
    this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: AppShadows.card,
        border: block.type == SmartBlockType.decision
            ? Border(
                left: BorderSide(
                  color: context.colors.accent,
                  width: 4,
                ),
              )
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Type label row
            Row(
              children: [
                _buildLeadingIcon(context),
                SizedBox(width: 10),
                Text(
                  _typeLabel.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: _labelColor(context),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                ),
                if (block.type == SmartBlockType.actionItem) ...[
                  SizedBox(width: 8),
                  _buildPriorityBadge(context),
                  const Spacer(),
                  GestureDetector(
                    onTap: onAssign,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: block.assignee != null 
                            ? context.colors.primaryLight 
                            : context.colors.textMuted.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.full),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_outline_rounded,
                            size: 13,
                            color: block.assignee != null ? context.colors.primary : context.colors.textMuted,
                          ),
                          SizedBox(width: 4),
                          Text(
                            block.assignee != null ? '@${block.assignee}' : 'Assign',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: block.assignee != null ? context.colors.primary : context.colors.textMuted,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                if (onEdit != null)
                  GestureDetector(
                    onTap: onEdit,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.edit_outlined, size: 16, color: context.colors.textLight),
                    ),
                  ),
              ],
            ),
            SizedBox(height: 12),
            // Content text
            Text(
              block.content,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    height: 1.6,
                    color: block.type == SmartBlockType.actionItem && block.isCompleted
                        ? context.colors.textMuted
                        : context.colors.textMain,
                    decoration: block.type == SmartBlockType.actionItem && block.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
            ),
            if (block.type == SmartBlockType.actionItem && block.dueDate != null) ...[
              SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 12, color: context.colors.textMuted),
                  SizedBox(width: 4),
                  Text(
                    'Due ${DateFormat('MMM d').format(block.dueDate!)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.colors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ],
              ),
            ],
            if (block.editedBy != null) ...[
              SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.history_edu_outlined, size: 13, color: context.colors.textLight),
                  SizedBox(width: 5),
                  Text(
                    block.editedAt != null
                        ? 'Edited by ${block.editedBy} · ${DateFormat('MMM d').format(block.editedAt!)}'
                        : 'Edited by ${block.editedBy}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.colors.textLight,
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 400.ms, curve: Curves.easeOut)
        .slideY(begin: 0.05, end: 0, duration: 400.ms, curve: Curves.easeOut);
  }

  Widget _buildLeadingIcon(BuildContext context) {
    switch (block.type) {
      case SmartBlockType.summary:
        return Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: context.colors.primaryLight,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.format_align_left_rounded,
            size: 16,
            color: context.colors.primary,
          ),
        );
      case SmartBlockType.decision:
        return Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: context.colors.accentLight,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.lightbulb_outline_rounded,
            size: 16,
            color: context.colors.accent,
          ),
        );
      case SmartBlockType.actionItem:
        return GestureDetector(
          onTap: onToggleComplete,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: block.isCompleted ? context.colors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color:
                    block.isCompleted ? context.colors.primary : context.colors.border,
                width: 2,
              ),
            ),
            child: block.isCompleted
                ? Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: Colors.white,
                  )
                : null,
          ),
        );
      case SmartBlockType.keyInsight:
        return Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: context.colors.textMuted.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.sticky_note_2_outlined,
            size: 16,
            color: context.colors.textMuted,
          ),
        );
    }
  }

  Widget _buildPriorityBadge(BuildContext context) {
    Color badgeColor;
    String label;
    switch (block.priority) {
      case SmartBlockPriority.high:
        badgeColor = Colors.red.shade400;
        label = 'HIGH';
        break;
      case SmartBlockPriority.medium:
        badgeColor = Colors.amber.shade700;
        label = 'MED';
        break;
      case SmartBlockPriority.low:
        badgeColor = Colors.blue.shade400;
        label = 'LOW';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: badgeColor,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  String get _typeLabel {
    switch (block.type) {
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

  Color _labelColor(BuildContext context) {
    switch (block.type) {
      case SmartBlockType.summary:
        return context.colors.primary;
      case SmartBlockType.decision:
        return context.colors.accent;
      case SmartBlockType.actionItem:
        return context.colors.primary;
      case SmartBlockType.keyInsight:
        return context.colors.textMuted;
    }
  }
}
