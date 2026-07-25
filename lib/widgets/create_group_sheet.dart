import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group.dart';
import '../providers/auth_provider.dart';
import '../repositories/firestore_repository.dart';
import '../theme/app_theme.dart';

const List<String> _kGroupEmojiChoices = ['👥', '🚀', '💡', '🎯', '📈', '🛠️', '🎨', '📚'];

/// Bottom sheet for creating a real group (name, description, emoji).
/// The creator is always added as the first member.
class CreateGroupSheet extends ConsumerStatefulWidget {
  const CreateGroupSheet({super.key});

  @override
  ConsumerState<CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends ConsumerState<CreateGroupSheet> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _selectedEmoji = _kGroupEmojiChoices.first;
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Give your group a name first.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final repo = ref.read(firestoreRepositoryProvider);
      final selfUser = ref.read(appUserProvider);
      final newGroup = Group(
        id: 'group_${DateTime.now().millisecondsSinceEpoch}',
        name: name,
        description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
        avatarEmoji: _selectedEmoji,
        members: [selfUser],
        memberJoinedAt: {selfUser.id: DateTime.now()},
        threadIds: [],
        createdBy: selfUser,
        createdAt: DateTime.now(),
        inviteCode: generateInviteCode(),
        adminIds: [selfUser.id],
      );
      await repo.createGroup(newGroup);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: context.colors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Create a Group',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: context.colors.textMain,
              ),
            ),
            const SizedBox(height: 20),

            // Emoji picker
            Wrap(
              spacing: 10,
              children: _kGroupEmojiChoices.map((emoji) {
                final isSelected = emoji == _selectedEmoji;
                return GestureDetector(
                  onTap: () => setState(() => _selectedEmoji = emoji),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isSelected ? context.colors.primaryLight : context.colors.background,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                      border: isSelected ? Border.all(color: context.colors.primary, width: 2) : null,
                    ),
                    child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Group name',
                hintText: 'e.g. Product Team',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                hintText: 'What is this group for?',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _createGroup,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        'Create Group',
                        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
