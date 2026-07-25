import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _onboardingSeenKey = 'onboarding_seen_v1';

/// Tracks whether the first-run tutorial has been completed. null = still
/// loading from disk (so we don't flash the tutorial before we know), true =
/// already seen, false = show it.
class OnboardingNotifier extends Notifier<bool?> {
  @override
  bool? build() {
    _load();
    return null;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_onboardingSeenKey) ?? false;
  }

  Future<void> markSeen() async {
    state = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onboardingSeenKey, true);
  }
}

final onboardingSeenProvider = NotifierProvider<OnboardingNotifier, bool?>(OnboardingNotifier.new);
