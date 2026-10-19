import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/data_providers.dart';
import '../theme/app_theme.dart';

/// Modal sheet to select teammates sitting in the same physical room sharing the user's microphone.
/// Writes to meetings/{meetingId}.coLocatedMap and presentParticipantIds so:
/// 1. Teammates are marked as present.
/// 2. Their reference voiceprint.ogg files are loaded for Gemini.
/// 3. Gemini receives an explicit SHARED MICROPHONE ALERT for this acoustic channel.
class CoLocatedParticipantsSheet extends ConsumerStatefulWidget {
  final String meetingId;
  final String? groupId;
  final List<String> initialSelectedIds;
  final ValueChanged<List<String>>? onSaved;

  const CoLocatedParticipantsSheet({
    super.key,
    required this.meetingId,
    this.groupId,
    this.initialSelectedIds = const [],
    this.onSaved,
  });

  static Future<List<String>?> show({
    required BuildContext context,
    required String meetingId,
    String? groupId,
    List<String> initialSelectedIds = const [],
    ValueChanged<List<String>>? onSaved,
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CoLocatedParticipantsSheet(
        meetingId: meetingId,
        groupId: groupId,
        initialSelectedIds: initialSelectedIds,
        onSaved: onSaved,
      ),
    );
  }

  @override
  ConsumerState<CoLocatedParticipantsSheet> createState() => _CoLocatedParticipantsSheetState();
}

class _CoLocatedParticipantsSheetState extends ConsumerState<CoLocatedParticipantsSheet> {
  final Set<String> _selectedUids = {};
  final TextEditingController _searchController = TextEditingController();
  bool _isSaving = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedUids.addAll(widget.initialSelectedIds);
    _loadExistingCoLocatedFromFirestore();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadExistingCoLocatedFromFirestore() async {
    final currentUserId = ref.read(currentUserProvider)?.uid;
    if (currentUserId == null) return;

    try {
      final doc = await FirebaseFirestore.instance.collection('meetings').doc(widget.meetingId).get();
      final data = doc.data();
      if (data != null && data['coLocatedMap'] is Map) {
        final coMap = data['coLocatedMap'] as Map<String, dynamic>;
        final guestList = coMap[currentUserId];
        if (guestList is List) {
          if (mounted) {
            setState(() {
              _selectedUids.addAll(guestList.map((e) => e.toString()));
            });
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _saveSelection() async {
    final currentUserId = ref.read(currentUserProvider)?.uid;
    if (currentUserId == null) return;

    setState(() => _isSaving = true);
    final selectedList = _selectedUids.toList();

    try {
      final meetingRef = FirebaseFirestore.instance.collection('meetings').doc(widget.meetingId);

      // Set coLocatedMap for this host and add to presentParticipantIds
      await meetingRef.set({
        'coLocatedMap': {
          currentUserId: selectedList,
        },
        if (selectedList.isNotEmpty)
          'presentParticipantIds': FieldValue.arrayUnion(selectedList),
      }, SetOptions(merge: true));

      widget.onSaved?.call(selectedList);

      if (mounted) {
        Navigator.of(context).pop(selectedList);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              selectedList.isEmpty
                ? 'Cleared shared microphone members.'
                : 'Linked ${selectedList.length} shared-mic teammate(s)! 🎙️',
            ),
            backgroundColor: context.colors.primary,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save shared mic members: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserProvider)?.uid;
    final groupsAsync = ref.watch(groupsProvider);

    List<AppUser> candidateUsers = [];
    final groups = groupsAsync.value ?? [];
    if (widget.groupId != null && widget.groupId != 'direct') {
      final match = groups.where((g) => g.id == widget.groupId).firstOrNull;
      if (match != null) {
        candidateUsers = match.members.where((u) => u.id != currentUserId).toList();
      }
    } else {
      final userMap = <String, AppUser>{};
      for (final g in groups) {
        for (final m in g.members) {
          if (m.id != currentUserId) {
            userMap[m.id] = m;
          }
        }
      }
      candidateUsers = userMap.values.toList();
    }

    final filteredUsers = candidateUsers.where((u) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return u.name.toLowerCase().contains(q) || u.email.toLowerCase().contains(q);
    }).toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: context.colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: context.colors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.people_alt_rounded, color: context.colors.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Person in my room (Shared Mic)',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textMain,
                      ),
                    ),
                    Text(
                      'Teammates sitting with you sharing your device\'s mic',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: context.colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Search input
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search teammates...',
              hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13, color: context.colors.textMuted),
              prefixIcon: Icon(Icons.search, size: 20, color: context.colors.textMuted),
              filled: true,
              fillColor: context.colors.background,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: context.colors.border),
              ),
            ),
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
          ),
          const SizedBox(height: 12),

          // Candidates list
          Expanded(
            child: filteredUsers.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        candidateUsers.isEmpty
                            ? 'No other group members found.\nGroup members can be added to your group to share a microphone.'
                            : 'No matching teammates found.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          color: context.colors.textMuted,
                          height: 1.4,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: filteredUsers.length,
                    separatorBuilder: (ctx, index) => Divider(height: 1, color: context.colors.border),
                    itemBuilder: (ctx, idx) {
                      final user = filteredUsers[idx];
                      final isSelected = _selectedUids.contains(user.id);

                      return CheckboxListTile(
                        value: isSelected,
                        activeColor: context.colors.primary,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        title: Text(
                          user.name,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: context.colors.textMain,
                          ),
                        ),
                        subtitle: Text(
                          user.email,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: context.colors.textMuted,
                          ),
                        ),
                        secondary: CircleAvatar(
                          radius: 18,
                          backgroundColor: context.colors.primary.withValues(alpha: 0.15),
                          child: Text(
                            user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                            style: TextStyle(
                              color: context.colors.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        onChanged: (checked) {
                          setState(() {
                            if (checked == true) {
                              _selectedUids.add(user.id);
                            } else {
                              _selectedUids.remove(user.id);
                            }
                          });
                        },
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveSelection,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Text('Save (${_selectedUids.length})'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
