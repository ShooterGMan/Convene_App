import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../providers/data_providers.dart';
import '../../providers/theme_provider.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/firestore_repository.dart';
import '../../models/user.dart';
import '../../widgets/voice_sample_recorder.dart';
import '../../widgets/profile_customizer_sheet.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _isDeletingAccount = false;

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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Settings',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textMain,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.task_alt_rounded, color: context.colors.primary),
                      tooltip: 'My Tasks & Productivity',
                      onPressed: () => context.push('/tasks'),
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Column(
                children: [
                  // ── 1. Profile Section ──
                  _buildSection(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            // Avatar with edit badge
                            GestureDetector(
                              onTap: () => ProfileCustomizerSheet.show(context, user: user),
                              child: Stack(
                                children: [
                                  Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: context.colors.primaryLight,
                                      border: Border.all(
                                        color: context.colors.border,
                                        width: 1,
                                      ),
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
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
                                  Positioned(
                                    bottom: 0,
                                    right: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: context.colors.primary,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: context.colors.surface, width: 2),
                                      ),
                                      child: const Icon(Icons.edit, size: 12, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
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
                                  const SizedBox(height: 2),
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
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => ProfileCustomizerSheet.show(context, user: user),
                              icon: const Icon(Icons.tune_rounded, size: 16),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: context.colors.primary,
                                side: BorderSide(color: context.colors.primary, width: 1.5),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(AppRadius.full),
                                ),
                              ),
                              label: Text(
                                'Customize',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, indent: 20, endIndent: 20),

                      // Voice ID Tile leading to Dashboard
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: user.hasVoiceprint
                                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                : context.colors.background,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(
                            user.hasVoiceprint ? Icons.record_voice_over_rounded : Icons.mic_none_rounded,
                            color: user.hasVoiceprint ? const Color(0xFF10B981) : context.colors.primary,
                            size: 22,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text('Voice ID (Voiceprint)', style: _tileTextStyle()),
                            const SizedBox(width: 8),
                            if (user.hasVoiceprint)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(AppRadius.full),
                                ),
                                child: const Text(
                                  'CALIBRATED',
                                  style: TextStyle(
                                    color: Color(0xFF10B981),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          user.hasVoiceprint
                              ? 'Voiceprint active · AI speaker attribution ready'
                              : 'Record a 5s sample for AI speaker attribution',
                          style: _tileSubtitleStyle(),
                        ),
                        trailing: Icon(Icons.chevron_right, color: context.colors.textLight),
                        onTap: () => _showVoiceIdDashboard(user),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── 2. Appearance Theme Selector ──
                  _buildSectionHeader('APPEARANCE'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildThemeSelector(),
                  ),
                  const SizedBox(height: 16),

                  // ── 3. Productivity & Tasks ──
                  _buildSectionHeader('PRODUCTIVITY & TASKS'),
                  _buildSection(
                    children: [
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: context.colors.primaryLight,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(Icons.insights_rounded, color: context.colors.primary, size: 22),
                        ),
                        title: Text('My Tasks & Productivity Hub', style: _tileTextStyle()),
                        subtitle: Text('Track cross-meeting action items & weekly stats', style: _tileSubtitleStyle()),
                        trailing: Icon(Icons.chevron_right, color: context.colors.textLight),
                        onTap: () => context.push('/tasks'),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── 4. Meeting Settings ──
                  _buildSectionHeader('MEETING SETTINGS'),
                  _buildSection(
                    children: [
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: context.colors.background,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(Icons.devices_rounded, color: context.colors.primary, size: 22),
                        ),
                        title: Text('Test Devices', style: _tileTextStyle()),
                        subtitle: Text('Check your camera and microphone', style: _tileSubtitleStyle()),
                        trailing: Icon(Icons.chevron_right, color: context.colors.textLight),
                        onTap: () {
                          context.push('/pre-join/test-room', extra: {
                            'title': 'Device Test',
                            'groupId': '',
                          });
                        },
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── 5. Integrations ──
                  _buildSectionHeader('INTEGRATIONS'),
                  _buildSection(
                    children: [
                      SwitchListTile.adaptive(
                        value: ref.watch(calendarAutoSyncProvider),
                        activeTrackColor: context.colors.primary,
                        secondary: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: context.colors.background,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(Icons.calendar_month_rounded, color: context.colors.primary, size: 22),
                        ),
                        title: Text('Google Calendar Auto-Sync', style: _tileTextStyle()),
                        subtitle: Text('Sync scheduled meetings to Google Calendar', style: _tileSubtitleStyle()),
                        onChanged: (val) {
                          ref.read(calendarAutoSyncProvider.notifier).toggle(val);
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(val
                                  ? 'Google Calendar Auto-Sync enabled'
                                  : 'Google Calendar Auto-Sync disabled'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── 6. Beta Testing ──
                  _buildSectionHeader('BETA TESTING'),
                  _buildSection(
                    children: [
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: context.colors.primaryLight,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(Icons.rate_review_rounded, color: context.colors.primary, size: 22),
                        ),
                        title: Text('Send Beta Feedback', style: _tileTextStyle()),
                        subtitle: Text('Report a bug, suggest a feature, or leave thoughts', style: _tileSubtitleStyle()),
                        trailing: Icon(Icons.chevron_right, color: context.colors.textLight),
                        onTap: _showFeedbackDialog,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── 7. Account ──
                  _buildSectionHeader('ACCOUNT'),
                  _buildSection(
                    children: [
                      ListTile(
                        title: Text(
                          'Delete Account',
                          style: _tileTextStyle().copyWith(color: Colors.redAccent),
                        ),
                        subtitle: Text(
                          'Permanently delete your account and profile data',
                          style: _tileSubtitleStyle(),
                        ),
                        trailing: _isDeletingAccount
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent),
                              )
                            : null,
                        onTap: _isDeletingAccount ? null : _confirmDeleteAccount,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── 8. About ──
                  _buildSectionHeader('ABOUT'),
                  _buildSection(
                    children: [
                      ListTile(
                        title: Text('Privacy Policy', style: _tileTextStyle()),
                        subtitle: Text('How Convene handles your audio, recordings & data', style: _tileSubtitleStyle()),
                        trailing: Icon(Icons.chevron_right, color: context.colors.textLight),
                        onTap: () => _showLegalDialog(
                          'Privacy Policy',
                          'Convene stores your name, email, meetings, and AI-generated summaries in Google Firebase, visible only to you and the other participants/group members on each meeting.\n\n'
                          'How recordings are handled: meeting audio is recorded, uploaded to Google Cloud Storage, and processed by Google Gemini to generate the written summary. The audio is deleted after the summary is created. Transcripts are kept for 30 days, then automatically deleted.\n\n'
                          'You are responsible for ensuring everyone in a meeting is aware it is being recorded.',
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      const Divider(height: 1, indent: 20, endIndent: 20),
                      ListTile(
                        title: Text('Contact & Support', style: _tileTextStyle()),
                        subtitle: Text('Get help or request a recording be deleted', style: _tileSubtitleStyle()),
                        trailing: Icon(Icons.chevron_right, color: context.colors.textLight),
                        onTap: () => _showLegalDialog(
                          'Contact support',
                          'For help, feedback, or data requests, email:\n\nshootergman12@gmail.com',
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),

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
                  const SizedBox(height: 32),
                ]
                    .animate(interval: 50.ms)
                    .fadeIn(duration: 350.ms)
                    .slideY(begin: 0.03, end: 0, duration: 350.ms, curve: Curves.easeOut),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Theme Selector Cards ──────────────────────────────────────

  Widget _buildThemeSelector() {
    final currentMode = ref.watch(themeModeProvider);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildThemeCard(
              mode: ThemeMode.system,
              label: 'System',
              icon: Icons.brightness_auto_rounded,
              isSelected: currentMode == ThemeMode.system,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildThemeCard(
              mode: ThemeMode.light,
              label: 'Light',
              icon: Icons.light_mode_rounded,
              isSelected: currentMode == ThemeMode.light,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _buildThemeCard(
              mode: ThemeMode.dark,
              label: 'Dark',
              icon: Icons.dark_mode_rounded,
              isSelected: currentMode == ThemeMode.dark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeCard({
    required ThemeMode mode,
    required String label,
    required IconData icon,
    required bool isSelected,
  }) {
    return GestureDetector(
      onTap: () => ref.read(themeModeProvider.notifier).setThemeMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? context.colors.primaryLight : context.colors.background,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: isSelected ? context.colors.primary : context.colors.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 22,
              color: isSelected ? context.colors.primary : context.colors.textMuted,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? context.colors.primary : context.colors.textMain,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Voice ID Calibration Dashboard ──────────────────────────

  void _showVoiceIdDashboard(AppUser user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _VoiceIdDashboardSheet(user: user),
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

  void _showLegalDialog(String title, String body) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showFeedbackDialog() async {
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: const Text('Send feedback'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(hintText: 'What\'s working, or what would make Convene better?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()), child: const Text('Send')),
        ],
      ),
    );

    if (message == null || message.isEmpty) return;
    final uid = ref.read(currentUserProvider)?.uid;
    if (uid != null) {
      try {
        await ref.read(firestoreRepositoryProvider).submitFeedback(userId: uid, kind: 'general', message: message);
      } catch (e) {
        debugPrint('Failed to submit feedback: $e');
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks for the feedback!')));
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: context.colors.surface,
        title: const Text('Delete Account?'),
        content: const Text(
          'This permanently deletes your profile. Groups, meetings, and threads you were part of will remain visible to other members. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeletingAccount = true);
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final uid = authRepo.currentUser?.uid;
      if (uid != null) {
        await ref.read(firestoreRepositoryProvider).deleteUser(uid);
      }
      await authRepo.deleteAccount();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            e.toString().contains('requires-recent-login')
                ? 'For security, please sign out and sign back in, then try again.'
                : 'Failed to delete account: $e',
          )),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeletingAccount = false);
    }
  }
}

// ─── VOICE ID DASHBOARD BOTTOM SHEET ──────────────────────────

class _VoiceIdDashboardSheet extends ConsumerStatefulWidget {
  final AppUser user;

  const _VoiceIdDashboardSheet({required this.user});

  @override
  ConsumerState<_VoiceIdDashboardSheet> createState() => _VoiceIdDashboardSheetState();
}

class _VoiceIdDashboardSheetState extends ConsumerState<_VoiceIdDashboardSheet> {
  @override
  Widget build(BuildContext context) {
    final hasVoiceprint = widget.user.hasVoiceprint;

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).padding.bottom + 20,
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Voice ID Dashboard',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textMain,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Status Banner Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: hasVoiceprint
                  ? const Color(0xFF10B981).withValues(alpha: 0.1)
                  : context.colors.primaryLight,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: hasVoiceprint
                    ? const Color(0xFF10B981).withValues(alpha: 0.3)
                    : context.colors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  hasVoiceprint ? Icons.verified_user_rounded : Icons.info_outline_rounded,
                  color: hasVoiceprint ? const Color(0xFF10B981) : context.colors.primary,
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasVoiceprint ? 'Voiceprint Calibrated & Active' : 'No Voiceprint Found',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: context.colors.textMain,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasVoiceprint
                            ? 'Gemini will automatically recognize and attribute your voice during recorded in-person meetings.'
                            : 'Record a quick 5-second voice sample so Convene can attribute your speech in meetings.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: context.colors.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Confidence & Accuracy Info
          if (hasVoiceprint) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.colors.background,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: context.colors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem('Audio Model', 'Opus 48kHz'),
                  Container(height: 24, width: 1, color: context.colors.border),
                  _buildStatItem('Sample Length', '5 Seconds'),
                  Container(height: 24, width: 1, color: context.colors.border),
                  _buildStatItem('AI Matching', 'Active 🎙️'),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // Actions
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const VoiceSampleRecorderSheet(),
                );
              },
              icon: Icon(hasVoiceprint ? Icons.refresh_rounded : Icons.mic_rounded, size: 18),
              label: Text(
                hasVoiceprint ? 'Re-calibrate / Update Sample' : 'Record 5s Voice Sample',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              ),
            ),
          ),

          if (hasVoiceprint) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dCtx) => AlertDialog(
                      backgroundColor: context.colors.surface,
                      title: const Text('Remove Voiceprint?'),
                      content: const Text(
                        'This will delete your recorded voiceprint profile. Convene won\'t be able to distinguish your voice in group meetings until you record a new one.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dCtx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(dCtx).pop(true),
                          child: const Text('Remove', style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true && mounted) {
                    final uid = ref.read(currentUserProvider)?.uid;
                    if (uid != null) {
                      await ref.read(firestoreRepositoryProvider).updateUserVoiceprintStatus(uid, false);
                      ref.invalidate(appUserProvider);
                    }
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Voiceprint removed')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
                label: const Text('Remove Voiceprint', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value) {
    return Column(
      children: [
        Text(value, style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 13, color: context.colors.textMain)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: context.colors.textMuted)),
      ],
    );
  }
}
