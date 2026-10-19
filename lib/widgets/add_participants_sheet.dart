import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/meeting.dart';
import '../models/user.dart';
import '../providers/data_providers.dart';
import '../repositories/firestore_repository.dart';
import '../theme/app_theme.dart';

class AddParticipantsSheet extends ConsumerStatefulWidget {
  final Meeting meeting;

  const AddParticipantsSheet({super.key, required this.meeting});

  @override
  ConsumerState<AddParticipantsSheet> createState() => _AddParticipantsSheetState();
}

class _AddParticipantsSheetState extends ConsumerState<AddParticipantsSheet> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _emailController = TextEditingController();
  bool _isSearching = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _linkGroup(String groupId) async {
    try {
      await ref.read(firestoreRepositoryProvider).updateMeeting(
        widget.meeting.id,
        {'groupId': groupId},
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error linking group: $e')));
      }
    }
  }

  Future<void> _addByEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorText = 'Enter an email address.');
      return;
    }

    setState(() {
      _isSearching = true;
      _errorText = null;
    });

    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('findUserByEmail')
          .call({'email': email});
      
      final data = result.data as Map;
      
      if (data['found'] != true) {
        setState(() {
          _isSearching = false;
          _errorText = 'No user found with that email.';
        });
        return;
      }

      final userData = data['user'] as Map;
      final newUser = AppUser(
        id: userData['id'],
        name: userData['name'],
        email: userData['email'],
        avatarUrl: userData['avatarUrl'],
      );

      final currentParticipants = widget.meeting.participants;
      if (currentParticipants.any((p) => p.id == newUser.id)) {
        setState(() {
          _isSearching = false;
          _errorText = 'User is already in the meeting.';
        });
        return;
      }

      final updatedParticipants = [...currentParticipants, newUser];
      
      await ref.read(firestoreRepositoryProvider).updateMeeting(
        widget.meeting.id,
        {'participants': updatedParticipants.map((p) => p.toJson()).toList()},
      );

      if (mounted) Navigator.pop(context);

    } catch (e) {
      setState(() {
        _isSearching = false;
        _errorText = 'Error finding user: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: context.colors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4, decoration: BoxDecoration(color: context.colors.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text('Mark Attendance', style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.bold, color: context.colors.textMain)),
          const SizedBox(height: 16),
          TabBar(
            controller: _tabController,
            labelColor: context.colors.primary,
            unselectedLabelColor: context.colors.textMuted,
            indicatorColor: context.colors.primary,
            tabs: const [
              Tab(text: 'Select Group'),
              Tab(text: 'Add by Email'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildGroupTab(),
                _buildEmailTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupTab() {
    final groupsAsync = ref.watch(groupsProvider);
    return groupsAsync.when(
      data: (groups) {
        if (groups.isEmpty) {
          return Center(child: Text('No groups found.', style: TextStyle(color: context.colors.textMuted)));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            final isSelected = widget.meeting.groupId == group.id;
            return ListTile(
              onTap: () => _linkGroup(group.id),
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: context.colors.surface, borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.group, color: context.colors.primary),
              ),
              title: Text(group.name, style: GoogleFonts.plusJakartaSans(color: context.colors.textMain, fontWeight: FontWeight.w600)),
              subtitle: Text('${group.members.length} members', style: TextStyle(color: context.colors.textMuted, fontSize: 13)),
              trailing: isSelected ? Icon(Icons.check_circle, color: context.colors.primary) : null,
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }

  Widget _buildEmailTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: TextStyle(color: context.colors.textMain),
            decoration: InputDecoration(
              labelText: 'User Email',
              labelStyle: TextStyle(color: context.colors.textMuted),
              filled: true,
              fillColor: context.colors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              errorText: _errorText,
            ),
            onSubmitted: (_) => _addByEmail(),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isSearching ? null : _addByEmail,
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _isSearching
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Add Participant', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
