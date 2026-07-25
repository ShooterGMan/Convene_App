import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../providers/onboarding_provider.dart';
import '../../theme/app_theme.dart';

class _Slide {
  final IconData icon;
  final String title;
  final String body;
  const _Slide({required this.icon, required this.title, required this.body});
}

const _slides = <_Slide>[
  _Slide(
    icon: Icons.auto_awesome_rounded,
    title: 'Meetings that write themselves up',
    body: 'Convene records your meetings and uses AI to create a summary with the '
        'key decisions and action items — so nobody has to take notes.',
  ),
  _Slide(
    icon: Icons.videocam_rounded,
    title: 'Start, schedule, or record',
    body: 'Tap the + button to start an online meeting now, schedule one for later, '
        'or record an in-person meeting happening in the room.',
  ),
  _Slide(
    icon: Icons.groups_rounded,
    title: 'Groups keep everyone in the loop',
    body: 'Create a group and invite your team. Every meeting summary is shared with '
        'the group automatically, and members can RSVP to upcoming meetings.',
  ),
  _Slide(
    icon: Icons.forum_rounded,
    title: 'Everything lives in Threads',
    body: 'Find every summary under the Threads tab — read the recap, check off '
        'action items, comment, and open the full transcript.',
  ),
];

/// First-run tutorial. Shown once (tracked in onboardingSeenProvider); a swipeable
/// set of slides explaining what the app does and how to do the core actions.
/// In [replayMode] (opened from Settings) it just pops when finished instead of
/// touching the seen flag.
class OnboardingScreen extends ConsumerStatefulWidget {
  final bool replayMode;

  const OnboardingScreen({super.key, this.replayMode = false});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _finish() {
    if (widget.replayMode) {
      Navigator.of(context).maybePop();
    } else {
      ref.read(onboardingSeenProvider.notifier).markSeen();
    }
  }

  void _next() {
    if (_page >= _slides.length - 1) {
      _finish();
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _slides.length - 1;

    return Scaffold(
      backgroundColor: context.colors.background,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _finish,
                child: Text(
                  'Skip',
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600, color: context.colors.textMuted),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _slides.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: context.colors.primaryLight.withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(s.icon, size: 56, color: context.colors.primary),
                        ),
                        const SizedBox(height: 40),
                        Text(
                          s.title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: context.colors.textMain,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          s.body,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            color: context.colors.textMuted,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Page dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_slides.length, (i) {
                final active = i == _page;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? context.colors.primary : context.colors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 32),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: context.colors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.full)),
                  ),
                  child: Text(
                    isLast ? 'Get Started' : 'Next',
                    style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
