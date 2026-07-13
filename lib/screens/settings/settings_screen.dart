import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_provider.dart';
import '../../repositories/auth_repository.dart';

import '../../theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Meeting Settings
  bool _autoRecord = true;
  bool _sendSummaries = true;

  // Integrations
  bool _calendarSync = true;

  // AI Preferences
  String _summaryLevel = 'Detailed';
  bool _speakerAttribution = true;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(appUserProvider);

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                child: Text(
                  'Settings',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textMain,
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Column(
                children: [
                  // ── Profile Section ──
                  _buildSection(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            // Avatar
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: context.colors.primaryLight,
                                border: Border.all(
                                    color: context.colors.border, width: 1),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: user.avatarUrl != null
                                  ? CachedNetworkImage(
                                      imageUrl: user.avatarUrl!,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          _profileInitials(user.initials),
                                      errorWidget: (context, url, error) =>
                                          _profileInitials(user.initials),
                                    )
                                  : _profileInitials(user.initials),
                            ),
                            SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user.name,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: context.colors.textMain,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    user.email,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: context.colors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () {},
                              style: OutlinedButton.styleFrom(
                                foregroundColor: context.colors.primary,
                                side: BorderSide(
                                    color: context.colors.primary, width: 1.5),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.full),
                                ),
                              ),
                              child: Text(
                                'Edit Profile',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),

                  // ── Meeting Settings ──
                  _buildSectionHeader('MEETING SETTINGS'),
                  _buildSection(
                    children: [
                      SwitchListTile(
                        title: Text(
                          'Auto-record meetings',
                          style: _tileTextStyle(),
                        ),
                        subtitle: Text(
                          'Automatically start recording when a session begins',
                          style: _tileSubtitleStyle(),
                        ),
                        value: _autoRecord,
                        onChanged: (v) => setState(() => _autoRecord = v),
                        activeThumbColor: context.colors.primary,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      Divider(height: 1, indent: 20, endIndent: 20),
                      SwitchListTile(
                        title: Text(
                          'Send summaries to group',
                          style: _tileTextStyle(),
                        ),
                        subtitle: Text(
                          'Automatically share Context Threads with group members',
                          style: _tileSubtitleStyle(),
                        ),
                        value: _sendSummaries,
                        onChanged: (v) => setState(() => _sendSummaries = v),
                        activeThumbColor: context.colors.primary,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),

                  // ── Integrations ──
                  _buildSectionHeader('INTEGRATIONS'),
                  _buildSection(
                    children: [
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: context.colors.background,
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(Icons.videocam,
                              color: context.colors.primary, size: 22),
                        ),
                        title: Text(
                          'Google Meet',
                          style: _tileTextStyle(),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: context.colors.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: 6),
                            Text(
                              'Connected',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: context.colors.accent,
                              ),
                            ),
                          ],
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      Divider(height: 1, indent: 20, endIndent: 20),
                      SwitchListTile(
                        title: Text(
                          'Google Calendar sync',
                          style: _tileTextStyle(),
                        ),
                        subtitle: Text(
                          'Import meetings from your Google Calendar',
                          style: _tileSubtitleStyle(),
                        ),
                        value: _calendarSync,
                        onChanged: (v) => setState(() => _calendarSync = v),
                        activeThumbColor: context.colors.primary,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),

                  // ── AI Preferences ──
                  _buildSectionHeader('AI PREFERENCES'),
                  _buildSection(
                    children: [
                      ListTile(
                        title: Text(
                          'Summary detail level',
                          style: _tileTextStyle(),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: context.colors.background,
                            borderRadius:
                                BorderRadius.circular(AppRadius.sm),
                            border: Border.all(color: context.colors.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _summaryLevel,
                              isDense: true,
                              icon: Icon(Icons.expand_more,
                                  size: 18, color: context.colors.textMuted),
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: context.colors.textMain,
                              ),
                              items: ['Concise', 'Detailed', 'Comprehensive']
                                  .map((level) => DropdownMenuItem(
                                        value: level,
                                        child: Text(level),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _summaryLevel = v);
                                }
                              },
                            ),
                          ),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      Divider(height: 1, indent: 20, endIndent: 20),
                      SwitchListTile(
                        title: Text(
                          'Speaker attribution',
                          style: _tileTextStyle(),
                        ),
                        subtitle: Text(
                          'Attribute quotes and actions to specific speakers',
                          style: _tileSubtitleStyle(),
                        ),
                        value: _speakerAttribution,
                        onChanged: (v) =>
                            setState(() => _speakerAttribution = v),
                        activeThumbColor: context.colors.primary,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      Divider(height: 1, indent: 20, endIndent: 20),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Custom Vocabulary',
                              style: _tileTextStyle(),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Ensure AI transcribes company jargon perfectly',
                              style: _tileSubtitleStyle(),
                            ),
                            SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildVocabChip('Stitch'),
                                _buildVocabChip('Convene'),
                                _buildVocabChip('PRD'),
                                ActionChip(
                                  backgroundColor: context.colors.background,
                                  side: BorderSide(color: context.colors.primary.withValues(alpha: 0.5)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
                                  label: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.add, size: 16, color: context.colors.primary),
                                      SizedBox(width: 4),
                                      Text(
                                        'Add',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: context.colors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                  onPressed: () {},
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),

                  // ── About ──
                  _buildSectionHeader('ABOUT'),
                  _buildSection(
                    children: [
                      ListTile(
                        title: Text('App Version', style: _tileTextStyle()),
                        trailing: Text(
                          '1.0.0',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: context.colors.textMuted,
                          ),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      Divider(height: 1, indent: 20, endIndent: 20),
                      ListTile(
                        title: Text('Terms of Service',
                            style: _tileTextStyle()),
                        trailing: Icon(Icons.chevron_right,
                            color: context.colors.textLight),
                        onTap: () {},
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      Divider(height: 1, indent: 20, endIndent: 20),
                      ListTile(
                        title: Text('Privacy Policy',
                            style: _tileTextStyle()),
                        trailing: Icon(Icons.chevron_right,
                            color: context.colors.textLight),
                        onTap: () {},
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ],
                  ),
                  SizedBox(height: 32),
                  // ── Sign Out ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () async {
                          await ref.read(authRepositoryProvider).signOut();
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                          side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                        ),
                        child: Text(
                          'Sign Out',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 32),
                ]
                    .animate(interval: 60.ms)
                    .fadeIn(duration: 350.ms)
                    .slideY(
                        begin: 0.04, end: 0, duration: 350.ms, curve: Curves.easeOut),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Text(
        title,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: context.colors.textMuted,
          letterSpacing: 1.0,
        ),
      ),
    );
  }

  Widget _buildSection({required List<Widget> children}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }

  Widget _profileInitials(String initials) {
    return Center(
      child: Text(
        initials,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: context.colors.primary,
        ),
      ),
    );
  }

  TextStyle _tileTextStyle() {
    return GoogleFonts.plusJakartaSans(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: context.colors.textMain,
    );
  }

  TextStyle _tileSubtitleStyle() {
    return GoogleFonts.plusJakartaSans(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: context.colors.textMuted,
    );
  }

  Widget _buildVocabChip(String label) {
    return Chip(
      backgroundColor: context.colors.primaryLight.withValues(alpha: 0.3),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
      label: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: context.colors.primary,
        ),
      ),
      onDeleted: () {},
      deleteIcon: Icon(Icons.close, size: 16, color: context.colors.primary),
    );
  }
}
