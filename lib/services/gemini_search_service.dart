import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../models/context_thread.dart';
import 'gemini_service.dart';

final geminiSearchServiceProvider = Provider<GeminiSearchService>((ref) {
  return GeminiSearchService();
});

class GeminiSearchService {
  late GenerativeModel _model;

  GeminiSearchService() {
    _model = GenerativeModel(
      model: 'text-embedding-004',
      apiKey: geminiApiKey,
    );
  }

  /// Calculates cosine similarity between two vectors
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  /// Get embedding for a single text
  Future<List<double>> getEmbedding(String text) async {
    if (geminiApiKey == 'YOUR_API_KEY') {
      await Future.delayed(const Duration(milliseconds: 100));
      // Return a dummy random vector for mocking purposes
      final r = Random();
      return List.generate(768, (_) => r.nextDouble());
    }

    try {
      final response = await _model.embedContent(
        Content.text(text),
      );
      return response.embedding.values;
    } catch (e) {
      throw Exception('Failed to get embedding: $e');
    }
  }

  /// Search across a mocked list of blocks
  /// In a production app with Firebase, this would use Firestore Vector Search.
  /// Here, we do local cosine similarity.
  Future<List<SmartBlock>> searchBlocks(String query, List<SmartBlock> allBlocks) async {
    try {
      final queryEmbedding = await getEmbedding(query);

      // In real life, we would cache block embeddings. 
      // For this local demo, we'll embed them on the fly if needed, or assume they are pre-embedded.
      // To save API calls and time, we'll simulate the search or limit the embeddings.
      // Let's actually embed them on the fly (limited to first 20 for safety).
      
      final targets = allBlocks.take(20).toList();
      
      List<Map<String, dynamic>> scoredBlocks = [];

      for (var block in targets) {
        final blockEmbedding = await getEmbedding(block.content);
        final score = _cosineSimilarity(queryEmbedding, blockEmbedding);
        scoredBlocks.add({
          'block': block,
          'score': score,
        });
      }

      // Sort by highest score first
      scoredBlocks.sort((a, b) => (b['score'] as double).compareTo(a['score'] as double));

      // Return top 3 matches
      return scoredBlocks
          .take(3)
          .map((e) => e['block'] as SmartBlock)
          .toList();

    } catch (e) {
      throw Exception('Search failed: $e');
    }
  }
}
