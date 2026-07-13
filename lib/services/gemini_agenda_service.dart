import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/context_thread.dart';
import 'gemini_service.dart';

final geminiAgendaServiceProvider = Provider<GeminiAgendaService>((ref) {
  return GeminiAgendaService();
});

class GeminiAgendaService {
  late GenerativeModel _model;

  GeminiAgendaService() {
    _model = GenerativeModel(
      model: 'gemini-3.0-pro',
      apiKey: geminiApiKey,
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
      ),
    );
  }

  Future<List<String>> generateMagicAgenda(List<SmartBlock> unresolvedTasks, String groupName) async {
    final tasksJson = unresolvedTasks.map((t) => {
      'content': t.content,
      'assignee': t.assignee,
    }).toList();

    final prompt = TextPart('''
You are a Meeting Intelligence AI. 
The user is preparing for the next "$groupName" meeting.
Here are the unresolved tasks from previous meetings:
${jsonEncode(tasksJson)}

Generate a concise, bulleted agenda for the upcoming meeting to address these items.
Output the result as a raw JSON array of strings, where each string is an agenda item.
Example: ["Review logo designs with Alex", "Finalize Q3 budget"]
''');

    try {
      if (geminiApiKey == 'YOUR_API_KEY') {
        await Future.delayed(const Duration(seconds: 2));
        return [
          "Review new logo designs",
          "Discuss Q3 budget constraints",
          "Finalize marketing strategy for launch"
        ];
      }

      final response = await _model.generateContent([
        Content.text(prompt.text)
      ]);

      final text = response.text;
      if (text == null) {
        throw Exception("Gemini returned a null response");
      }

      final List<dynamic> jsonResponse = jsonDecode(text);
      return jsonResponse.map((e) => e.toString()).toList();

    } catch (e) {
      throw Exception('Failed to generate magic agenda: $e');
    }
  }
}
