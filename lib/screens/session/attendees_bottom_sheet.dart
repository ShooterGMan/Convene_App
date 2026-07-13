import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/meeting.dart';
import '../../models/user.dart';
import '../../theme/app_theme.dart';

class AttendeesBottomSheet extends StatefulWidget {
  final Meeting meeting;

  const AttendeesBottomSheet({super.key, required this.meeting});

  /// Show the attendees bottom sheet. Returns `true` if 'Start Session' was tapped.
  static Future<bool?> show(BuildContext context, Meeting meeting) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.colors.overlay,
      builder: (_) => AttendeesBottomSheet(meeting: meeting),
    );
  }

  @override
  State<AttendeesBottomSheet> createState() => _AttendeesBottomSheetState();
}

class _AttendeesBottomSheetState extends State<AttendeesBottomSheet> {
  late final Map<String, bool> _toggles;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _toggles = {
      for (final p in widget.meeting.participants) p.id: true,
    };
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AppUser> get _filteredParticipants {
    if (_searchQuery.isEmpty) return widget.meeting.participants;
    final q = _searchQuery.toLowerCase();
    return widget.meeting.participants
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.email.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomPadding = MediaQuery.of(context).viewPadding.bottom;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      child: Container(
        height: screenHeight * 0.85,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(AppRadius.md),
            topRight: Radius.circular(AppRadius.md),
          ),
        ),
        child: Column(
          children: [
            // Handle bar
            _buildHandleBar(),
            // Header
            _buildHeader(context),
            Divider(height: 1, color: context.colors.divider),
            // Search
            _buildSearchInput(),
            // Participant list
            Expanded(child: _buildParticipantList()),
            // Magic Agenda
            _buildMagicAgenda(),
            // Info banner
            _buildInfoBanner(),
            // Start Session button
            _buildStartButton(context, bottomPadding),
          ],
        ),
      ),
    ).animate().slideY(
          begin: 1.0,
          end: 0.0,
          duration: 400.ms,
          curve: Curves.easeOutCubic,
        );
  }

  Widget _buildHandleBar() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Center(
        child: Container(
          width: 48,
          height: 6,
          decoration: BoxDecoration(
            color: context.colors.textLight,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${widget.meeting.title} Attendees',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: context.colors.textMain,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(width: 12),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(AppRadius.full),
              ),
              child: Icon(
                Icons.close,
                size: 20,
                color: context.colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: TextField(
        controller: _searchController,
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Invite via Gmail...',
          prefixIcon: Icon(Icons.search, color: context.colors.textMuted),
          filled: true,
          fillColor: context.colors.background,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide(color: context.colors.primary, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        ),
      ),
    );
  }

  Widget _buildParticipantList() {
    final participants = _filteredParticipants;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        // Section header
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            'INVITED (${participants.length})',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: context.colors.textMuted,
              letterSpacing: 1.0,
            ),
          ),
        ),
        // Participant rows
        ...List.generate(participants.length, (index) {
          final user = participants[index];
          final isChecked = _toggles[user.id] ?? false;
          return _buildParticipantRow(user, isChecked, index);
        }),
      ],
    );
  }

  Widget _buildParticipantRow(AppUser user, bool isChecked, int index) {
    final isSelf = user.isSelf;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isChecked ? 1.0 : 0.7,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            // Avatar
            _buildAvatar(user),
            SizedBox(width: 14),
            // Name & email
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textMain,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 2),
                  Text(
                    user.email,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: context.colors.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            // Toggle switch
            Opacity(
              opacity: isSelf ? 0.5 : 1.0,
              child: IgnorePointer(
                ignoring: isSelf,
                child: Switch.adaptive(
                  value: isChecked,
                  onChanged: (value) {
                    setState(() {
                      _toggles[user.id] = value;
                    });
                  },
                  activeThumbColor: context.colors.primary,
                  activeTrackColor: context.colors.primaryLight,
                ),
              ),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(
          delay: Duration(milliseconds: 50 * index),
          duration: 300.ms,
        )
        .slideX(
          begin: 0.05,
          end: 0,
          delay: Duration(milliseconds: 50 * index),
          duration: 300.ms,
          curve: Curves.easeOut,
        );
  }

  Widget _buildAvatar(AppUser user) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.colors.primaryLight,
        border: Border.all(color: context.colors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: user.avatarUrl != null
          ? CachedNetworkImage(
              imageUrl: user.avatarUrl!,
              fit: BoxFit.cover,
              placeholder: (context, url) => _initialsWidget(user),
              errorWidget: (context, url, error) => _initialsWidget(user),
            )
          : _initialsWidget(user),
    );
  }

  Widget _initialsWidget(AppUser user) {
    return Center(
      child: Text(
        user.initials,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: context.colors.primary,
        ),
      ),
    );
  }

  Widget _buildMagicAgenda() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.colors.primary.withValues(alpha: 0.3)),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: context.colors.primary),
              SizedBox(width: 8),
              Text(
                'MAGIC AGENDA',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: context.colors.primary,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            'Based on previous context threads, here are suggested topics:',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: context.colors.textMuted,
            ),
          ),
          SizedBox(height: 12),
          _buildAgendaItem('Review Tailwind v3 Migration PRD'),
          SizedBox(height: 8),
          _buildAgendaItem('Cost analysis for cloud scaling'),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms, delay: 200.ms).slideY(begin: 0.1, end: 0, delay: 200.ms);
  }

  Widget _buildAgendaItem(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_box_outlined, size: 20, color: context.colors.primary),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.colors.textMain,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.accentLight,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: context.colors.accent,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Toggled participants will receive the Context Thread automatically after the session ends.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: context.colors.textMain,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStartButton(BuildContext context, double bottomPadding) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPadding + 16),
      child: Container(
        decoration: BoxDecoration(
          boxShadow: AppShadows.diffused,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: Icon(Icons.mic, size: 20),
          label: Text(
            'Start Session',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: context.colors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            elevation: 0,
          ),
        ),
      ),
    );
  }
}
