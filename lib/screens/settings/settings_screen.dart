import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../build_info.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_providers.dart';
import '../../providers/theme_provider.dart';
import '../../repositories/auth_repository.dart';
import '../../repositories/firestore_repository.dart';
import '../../models/user.dart';
import '../onboarding/onboarding_screen.dart';

import '../../widgets/voice_sample_recorder.dart';
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
                              onPressed: () => _editProfile(user.name),
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
                      const Divider(height: 1, indent: 20, endIndent: 20),
                      ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: user.hasVoiceprint ? context.colors.primaryLight : context.colors.background,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(
                            user.hasVoiceprint ? Icons.record_voice_over_rounded : Icons.mic_none_rounded,
                            color: context.colors.primary,
                            size: 22,
                          ),
                        ),
                        title: Text('Voice ID (Voiceprint)', style: _tileTextStyle()),
                        subtitle: Text(
                          user.hasVoiceprint ? 'Voice ID Active 🎙️ · Tap to update sample' : 'Record 5s sample for AI voice recognition',
                          style: _tileSubtitleStyle(),
                        ),
                        trailing: Icon(Icons.chevron_right, color: context.colors.textLight),
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (context) => const VoiceSampleRecorderSheet(),
                          );
                        },
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),

                  // ── Meeting Settings ──
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
                          child: Icon(Icons.devices, color: context.colors.primary, size: 22),
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
                  SizedBox(height: 12),

                  // ── Integrations ──
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
                              content: Text(val ? 'Google Calendar Auto-Sync enabled' : 'Google Calendar Auto-Sync disabled'),
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        },
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),

                  // ── Appearance ──
                  _buildSectionHeader('APPEARANCE'),
                  _buildSection(
                    children: [
                      _buildThemeOption(ThemeMode.system, 'System', 'Match your device setting'),
                      Divider(height: 1, indent: 20, endIndent: 20),
                      _buildThemeOption(ThemeMode.light, 'Light', ''),
                      Divider(height: 1, indent: 20, endIndent: 20),
                      _buildThemeOption(ThemeMode.dark, 'Dark', ''),
                    ],
                  ),
                  SizedBox(height: 12),

                  // ── Beta Feedback ──
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
                  SizedBox(height: 12),

                  // ── Account ──
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
                            ? SizedBox(
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
                  SizedBox(height: 12),

                  // ── About ──
                  _buildSectionHeader('ABOUT'),
                  _buildSection(
                    children: [
                      ListTile(
                        title: Text('Build', style: _tileTextStyle()),
                        subtitle: Text(
                          'If this doesn\'t match what you were just given, you\'re on a stale cached/old build.',
                          style: _tileSubtitleStyle(),
                        ),
                        trailing: Text(
                          kBuildStamp,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: context.colors.textMuted,
                          ),
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      Divider(height: 1, indent: 20, endIndent: 20),
                      ListTile(
                        title: Text('How Convene works', style: _tileTextStyle()),
                        subtitle: Text('Replay the intro tutorial', style: _tileSubtitleStyle()),
                        trailing: Icon(Icons.chevron_right, color: context.colors.textLight),
                        onTap: () {
                          Navigator.of(context).push(MaterialPageRoute(
                            builder: (_) => const OnboardingScreen(replayMode: true),
                          ));
                        },
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      Divider(height: 1, indent: 20, endIndent: 20),
                      ListTile(
                        title: Text('Terms of Service',
                            style: _tileTextStyle()),
                        trailing: Icon(Icons.chevron_right,
                            color: context.colors.textLight),
                        onTap: () => _showLegalDialog(
                          'Terms of Service',
                          'Convene is currently in private testing. By using this build you '
                              'agree that features and data may change or be reset without '
                              'notice. A finalized Terms of Service will be published before '
                              'any public release.',
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      Divider(height: 1, indent: 20, endIndent: 20),
                      ListTile(
                        title: Text('Privacy Policy',
                            style: _tileTextStyle()),
                        trailing: Icon(Icons.chevron_right,
                            color: context.colors.textLight),
                        onTap: () => _showLegalDialog(
                          'Privacy Policy',
                          'Convene stores your name, email, meetings, and AI-generated '
                              'summaries in Google Firebase, visible only to you and the '
                              'other participants/group members on each meeting.\n\n'
                              'How recordings are handled: meeting audio is recorded, uploaded '
                              'to Google Cloud Storage, and processed by Google Gemini (a '
                              'third-party AI service) to generate the written summary. The '
                              'audio is deleted after the summary is created. Transcripts are '
                              'kept for 30 days, then automatically deleted.\n\n'
                              'You are responsible for ensuring everyone in a meeting is aware '
                              'it is being recorded. Deleting your account removes your profile; '
                              'to request deletion of a specific recording or summary, use the '
                              'support contact below.\n\n'
                              'Convene is in private testing; a finalized Privacy Policy will '
                              'be published before any public release.',
                        ),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      Divider(height: 1, indent: 20, endIndent: 20),
                      ListTile(
                        title: Text('Contact & data requests', style: _tileTextStyle()),
                        subtitle: Text('Get help or request a recording be deleted', style: _tileSubtitleStyle()),
                        trailing: Icon(Icons.chevron_right, color: context.colors.textLight),
                        onTap: () => _showLegalDialog(
                          'Contact support',
                          'For help, feedback, or to request deletion of a meeting recording or '
                              'summary, email:\n\nshootergman12@gmail.com\n\n'
                              '(A dedicated support address will replace this before public launch.)',
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                      ),
                      ListTile(
                        title: Text('Send feedback', style: _tileTextStyle()),
                        subtitle: Text('Tell us what\'s working or what\'s missing', style: _tileSubtitleStyle()),
                        trailing: Icon(Icons.chevron_right, color: context.colors.textLight),
                        onTap: _showFeedbackDialog,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
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

  void _showLegalDialog(String title, String body) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(body)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Close'),
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

  Future<void> _editProfile(String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Edit Profile'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: 'Display name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text('Save'),
          ),
        ],
      ),
    );

    if (newName == null || newName.isEmpty || newName == currentName || !mounted) return;

    try {
      final authUser = ref.read(authRepositoryProvider).currentUser;
      if (authUser == null) return;
      await authUser.updateDisplayName(newName);
      await authUser.reload();
      final refreshed = ref.read(authRepositoryProvider).currentUser;
      if (refreshed != null) {
        await ref.read(firestoreRepositoryProvider).createUser(AppUser(
              id: refreshed.uid,
              name: newName,
              email: refreshed.email ?? '',
              avatarUrl: refreshed.photoURL,
              isSelf: true,
            ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update profile: $e')),
        );
      }
    }
  }

  Widget _buildThemeOption(ThemeMode mode, String label, String subtitle) {
    final currentMode = ref.watch(themeModeProvider);
    final isSelected = currentMode == mode;
    return ListTile(
      leading: Icon(
        isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
        color: isSelected ? context.colors.primary : context.colors.textMuted,
        size: 22,
      ),
      title: Text(label, style: _tileTextStyle()),
      subtitle: subtitle.isNotEmpty ? Text(subtitle, style: _tileSubtitleStyle()) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      onTap: () {
        ref.read(themeModeProvider.notifier).setThemeMode(mode);
      },
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete Account?'),
        content: Text(
          'This permanently deletes your profile. Groups, meetings, and threads you were part of will remain visible to other members. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
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
