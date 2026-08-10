import 'package:flutter/material.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';

import '../../theme/app_theme.dart';

/// Landed on when someone opens a shared group invite link
/// (https://.../#/join-group/{inviteCode}). Joining via a link they chose to
/// open is itself the consent, so this joins immediately rather than
/// requiring a separate accept step.
class JoinGroupScreen extends StatefulWidget {
  final String inviteCode;

  const JoinGroupScreen({super.key, required this.inviteCode});

  @override
  State<JoinGroupScreen> createState() => _JoinGroupScreenState();
}

class _JoinGroupScreenState extends State<JoinGroupScreen> {
  bool _isLoading = true;
  String? _error;
  String? _groupId;
  String? _groupName;
  bool _alreadyMember = false;

  @override
  void initState() {
    super.initState();
    _join();
  }

  Future<void> _join() async {
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable('joinGroupByInviteLink').call({
        'inviteCode': widget.inviteCode,
      });
      final data = result.data as Map;
      if (mounted) {
        setState(() {
          _isLoading = false;
          _groupId = data['groupId'] as String?;
          _groupName = data['groupName'] as String?;
          _alreadyMember = data['alreadyMember'] == true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isLoading) ...[
                CircularProgressIndicator(color: context.colors.primary),
                const SizedBox(height: 24),
                Text(
                  'Joining group...',
                  style: GoogleFonts.plusJakartaSans(fontSize: 16, color: context.colors.textMuted),
                ),
              ] else if (_error != null) ...[
                Icon(Icons.error_outline_rounded, size: 48, color: context.colors.error),
                const SizedBox(height: 16),
                Text(
                  'Couldn\'t join group',
                  style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: context.colors.textMain),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, color: context.colors.textMuted),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.go('/groups'),
                  child: const Text('Go to Groups'),
                ),
              ] else ...[
                Icon(Icons.check_circle_rounded, size: 48, color: context.colors.primary),
                const SizedBox(height: 16),
                Text(
                  _alreadyMember ? 'You\'re already in "${_groupName ?? "this group"}"' : 'Joined "${_groupName ?? "the group"}"!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700, color: context.colors.textMain),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => context.go(_groupId != null ? '/group/$_groupId' : '/groups'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Open Group'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
