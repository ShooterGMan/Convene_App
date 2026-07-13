import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/context_thread.dart';
import '../models/group.dart';
import '../models/meeting.dart';
import '../data/mock_data.dart';
import '../services/gemini_service.dart';
import '../repositories/firestore_repository.dart';

final meetingsProvider = StreamProvider<List<Meeting>>((ref) async* {
  if (geminiApiKey == 'YOUR_API_KEY') {
    yield MockMeetings.upcoming;
  } else {
    yield* ref.watch(firestoreRepositoryProvider).streamMeetings();
  }
});

final threadsProvider = StreamProvider<List<ContextThread>>((ref) async* {
  if (geminiApiKey == 'YOUR_API_KEY') {
    yield MockThreads.threads;
  } else {
    yield* ref.watch(firestoreRepositoryProvider).streamThreads();
  }
});

final groupsProvider = StreamProvider<List<Group>>((ref) async* {
  if (geminiApiKey == 'YOUR_API_KEY') {
    yield MockGroups.groups;
  } else {
    yield* ref.watch(firestoreRepositoryProvider).streamGroups();
  }
});
