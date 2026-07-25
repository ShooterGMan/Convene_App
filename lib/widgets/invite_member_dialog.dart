import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/group.dart';
import '../theme/app_theme.dart';

/// Dialog that invites an existing user by email via the sendGroupInvite
/// Cloud Function. This creates a *pending* invite rather than adding them
/// directly - the invited person has to accept it themselves.
class InviteMemberDialog extends ConsumerStatefulWidget {
  final Group group;

  const InviteMemberDialog({super.key, required this.group});

  @override
  ConsumerState<InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends ConsumerState<InviteMemberDialog> {
  final _emailController = TextEditingController();
  bool _isSending = false;
  String? _errorText;
  bool _noAccountFound = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

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
      final result = await FirebaseFunctions.instance.httpsCallable('sendGroupInvite').call({
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
          const SnackBar(content: Text('Invite sent! They can accept it from their Groups tab.')),
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
    final link = 'https://meeting-app-844aa.web.app/join-group/${widget.group.inviteCode}';
    Clipboard.setData(ClipboardData(text: link));
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Invite link copied - send it to them any way you like.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_noAccountFound) {
      return AlertDialog(
        title: Text(
          'No Convene account yet',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        content: Text(
          'That email hasn\'t signed in to Convene yet, so they can\'t get an in-app invite. '
          'Copy the group\'s invite link instead and send it to them directly (text, email, etc.) - '
          'opening it will get them signed up and straight into the group.',
          style: GoogleFonts.plusJakartaSans(fontSize: 13, color: context.colors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => setState(() => _noAccountFound = false),
            child: const Text('Back'),
          ),
          ElevatedButton(
            onPressed: _copyInviteLink,
            style: ElevatedButton.styleFrom(
              backgroundColor: context.colors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Copy Invite Link'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: Text(
        'Invite by Email',
        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'They\'ll get an invite to accept or decline in-app if they\'ve already signed in to Convene - otherwise we\'ll offer you a link to send them directly.',
            style: GoogleFonts.plusJakartaSans(fontSize: 13, color: context.colors.textMuted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _emailController,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'name@example.com',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm)),
              errorText: _errorText,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSending ? null : _invite,
          style: ElevatedButton.styleFrom(
            backgroundColor: context.colors.primary,
            foregroundColor: Colors.white,
          ),
          child: _isSending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
              : const Text('Send Invite'),
        ),
      ],
    );
  }
}
