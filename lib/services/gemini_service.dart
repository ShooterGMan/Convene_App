import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../models/context_thread.dart';
import '../models/user.dart';

String get geminiApiKey => dotenv.env['GEMINI_API_KEY'] ?? 'YOUR_API_KEY';

final geminiServiceProvider = Provider<GeminiMeetingService>((ref) {
  return GeminiMeetingService();
});

class GeminiMeetingService {
  late GenerativeModel _model;

  GeminiMeetingService() {
    _model = GenerativeModel(
      model: 'gemini-3.0-pro',
      apiKey: geminiApiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );
  }

  Future<ContextThread> processMeetingAudio(String filePath, String meetingTitle, List<AppUser> participants) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    
    // Convert m4a to mime type audio/mp4
    final audioPart = DataPart('audio/mp4', bytes);
    
    final participantNames = participants.map((p) => p.name).join(', ');
    final prompt = TextPart('''
You are a highly advanced Meeting Intelligence AI. 
Analyze the provided meeting audio and extract the key information.

The following people are participants in this meeting: $participantNames. Use these names to accurately identify who action items are assigned to.

Output the result as a raw JSON object matching the following structure exactly (without markdown blocks):
{
  "meetingTitle": "$meetingTitle",
  "vibe": "A 2-3 word description of the meeting's vibe",
  "vibeEmoji": "A single emoji representing the vibe",
  "blocks": [
    {
      "id": "uuid",
      "type": "decision|actionItem|keyInsight",
      "content": "The actual text content",
      "assignee": "Name of person assigned (only for actionItem, null otherwise)",
      "isCompleted": false,
      "reactions": []
    }
  ]
}

Focus heavily on identifying decisions made, action items assigned to specific people, and critical insights discussed.
''');

    try {
      if (geminiApiKey == 'YOUR_API_KEY') {
        // Fallback for testing without API key
        await Future.delayed(const Duration(seconds: 3));
        return ContextThread(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          meetingTitle: meetingTitle,
          createdAt: DateTime.now(),
          participants: [],
          vibe: 'Productive & Focused',
          vibeEmoji: '🚀',
          blocks: [
            SmartBlock(
              id: '1',
              type: SmartBlockType.decision,
              content: 'Decided to move forward with the Flutter redesign.',
            ),
            SmartBlock(
              id: '2',
              type: SmartBlockType.actionItem,
              content: 'Create high-fidelity mockups for the new dashboard.',
              assignee: 'Sarah',
            ),
            SmartBlock(
              id: '3',
              type: SmartBlockType.keyInsight,
              content: 'Users are requesting better offline support.',
            ),
          ],
        );
      }

      final response = await _model.generateContent([
        Content.multi([prompt, audioPart])
      ]);

      final text = response.text;
      if (text == null) {
        throw Exception("Gemini returned a null response");
      }

      final Map<String, dynamic> jsonResponse = jsonDecode(text);
      
      // Parse blocks
      List<SmartBlock> parsedBlocks = [];
      if (jsonResponse['blocks'] != null) {
        for (var b in jsonResponse['blocks']) {
          parsedBlocks.add(SmartBlockJson.fromJson(b));
        }
      }

      return ContextThread(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        meetingTitle: jsonResponse['meetingTitle'] ?? meetingTitle,
        createdAt: DateTime.now(),
        participants: [], // In a real app, populate from meeting data
        blocks: parsedBlocks,
        vibe: jsonResponse['vibe'],
        vibeEmoji: jsonResponse['vibeEmoji'],
      );

    } catch (e) {
      throw Exception('Failed to process meeting audio with Gemini: $e');
    }
  }
}
