import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/group.dart';
import '../theme/app_theme.dart';

/// Dialog with Email Invite and Instant QR Code / Link tabs.
class InviteMemberDialog extends ConsumerStatefulWidget {
  final Group group;

  const InviteMemberDialog({super.key, required this.group});

  @override
  ConsumerState<InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends ConsumerState<InviteMemberDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _emailController = TextEditingController();
  bool _isSending = false;
  String? _errorText;
  bool _noAccountFound = false;

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

  String get _inviteUrl =>
      'https://meeting-app-844aa.web.app/join-group/${widget.group.inviteCode}';

  Future<void> _invite() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _errorText = 'Enter an email address.');
      return;
    }

    setState(() {
      _isSending = true;
      _errorText = null;
    });

    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('sendGroupInvite')
          .call({
        'groupId': widget.group.id,
        'email': email,
      });
      final data = result.data as Map;

      if (data['found'] != true) {
        setState(() {
          _isSending = false;
          _noAccountFound = true;
        });
        return;
      }

      if (data['alreadyMember'] == true) {
        setState(() {
          _isSending = false;
          _errorText = 'That person is already in this group.';
        });
        return;
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Invite sent! They can accept it from their Groups tab.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSending = false;
          _errorText = 'Something went wrong: $e';
        });
      }
    }
  }

  void _copyInviteLink() {
    Clipboard.setData(ClipboardData(text: _inviteUrl));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Invite link copied! Anyone who opens it can join this group.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_noAccountFound) {
      return AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg)),
        title: Text(
          'No Convene account yet',
          style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700, color: context.colors.textMain),
        ),
        content: Text(
          'That email hasn\'t signed in to Convene yet, so they can\'t get an in-app invite. '
          'Share the group\'s invite link or QR code instead and send it to them directly.',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 13, color: context.colors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _noAccountFound = false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: () {
              _copyInviteLink();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Copy Invite Link'),
          ),
        ],
      );
    }

    return Dialog(
      backgroundColor: context.colors.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Invite to "${widget.group.name}"',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: context.colors.textMain,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabController,
              labelColor: context.colors.primary,
              unselectedLabelColor: context.colors.textMuted,
              indicatorColor: context.colors.primary,
              indicatorWeight: 3,
              labelStyle: GoogleFonts.plusJakartaSans(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              tabs: const [
                Tab(text: 'By Email'),
                Tab(text: 'QR Code & Link'),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 280,
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: Email Invite
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'They\'ll get an in-app invite to accept directly from their Convene feed.',
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 13, color: context.colors.textMuted),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _emailController,
                        autofocus: true,
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(color: context.colors.textMain),
                        decoration: InputDecoration(
                          hintText: 'colleague@company.com',
                          hintStyle: TextStyle(color: context.colors.textMuted),
                          filled: true,
                          fillColor: context.colors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            borderSide: BorderSide(color: context.colors.border),
                          ),
                          errorText: _errorText,
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSending ? null : _invite,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: context.colors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                          ),
                          child: _isSending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : const Text('Send In-App Invite',
                                  style: TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),

                  // Tab 2: QR Code & Link
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: context.colors.border),
                        ),
                        child: QrImageView(
                          data: _inviteUrl,
                          version: QrVersions.auto,
                          size: 140,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: context.colors.background,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          border: Border.all(color: context.colors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Code: ',
                              style: TextStyle(
                                  fontSize: 12, color: context.colors.textMuted),
                            ),
                            SelectableText(
                              widget.group.inviteCode,
                              style: GoogleFonts.firaCode(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: context.colors.primary,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _copyInviteLink,
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: const Text('Copy Shareable Link',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: context.colors.primary,
                            side: BorderSide(color: context.colors.primary),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
