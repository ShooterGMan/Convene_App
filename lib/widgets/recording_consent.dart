import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

/// Plain-language disclosure of what recording a meeting entails. Kept in one
/// place so the pre-join notice, the offline consent gate, and the privacy
/// text all say the same thing.
const String kRecordingDisclosure =
    'This meeting is recorded and its audio is processed by AI (Google Gemini) '
    'to generate a written summary. Audio is deleted after the summary is made; '
    'transcripts are kept for 30 days. The summary is shared with the meeting\'s '
    'participants and group.';

/// Compact inline notice shown on the pre-join screen. Joining is the consent
/// action (same model as Zoom/Meet recording banners).
class RecordingConsentNotice extends StatelessWidget {
  const RecordingConsentNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.primaryLight.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: context.colors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.fiber_manual_record, size: 14, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$kRecordingDisclosure\n\nBy joining, you agree to this.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                height: 1.4,
                color: context.colors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen consent gate for the in-person recording flow. Recording people
/// physically in a room means the recorder must confirm everyone present agreed
/// - the people in the room aren't app users who can consent for themselves.
class OfflineRecordingConsentGate extends StatefulWidget {
  final VoidCallback onConsent;
  final VoidCallback onCancel;

  const OfflineRecordingConsentGate({super.key, required this.onConsent, required this.onCancel});

  @override
  State<OfflineRecordingConsentGate> createState() => _OfflineRecordingConsentGateState();
}

class _OfflineRecordingConsentGateState extends State<OfflineRecordingConsentGate> {
  bool _everyoneAgreed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(
        backgroundColor: context.colors.background,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.close), onPressed: widget.onCancel),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: context.colors.primaryLight.withValues(alpha: 0.4), shape: BoxShape.circle),
                child: Icon(Icons.mic_rounded, size: 34, color: context.colors.primary),
              ),
              const SizedBox(height: 24),
              Text(
                'Before you record',
                style: GoogleFonts.plusJakartaSans(fontSize: 24, fontWeight: FontWeight.w800, color: context.colors.textMain),
              ),
              const SizedBox(height: 12),
              Text(
                kRecordingDisclosure,
                style: GoogleFonts.plusJakartaSans(fontSize: 14, height: 1.5, color: context.colors.textMuted),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  'You are responsible for telling everyone in the room they are being recorded and getting their agreement. '
                  'In some places recording without everyone\'s consent is illegal.',
                  style: GoogleFonts.plusJakartaSans(fontSize: 13, height: 1.4, color: context.colors.textMain),
                ),
              ),
              const SizedBox(height: 12),
              CheckboxListTile(
                value: _everyoneAgreed,
                onChanged: (v) => setState(() => _everyoneAgreed = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                activeColor: context.colors.primary,
                title: Text(
                  'Everyone here has agreed to be recorded',
                  style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600, color: context.colors.textMain),
                ),
              ),
              const Spacer(),
              ElevatedButton(
                onPressed: _everyoneAgreed ? widget.onConsent : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: context.colors.primary.withValues(alpha: 0.4),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
                ),
                child: Text('Start recording', style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
