import 'dart:typed_data';

import 'package:academy_management/config/app_config.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

/// Single entry point for every Gemini AI call in the app.
class GeminiService {
  const GeminiService._();

  static bool get isConfigured => AppConfig.hasGeminiApiKey;

  static GenerativeModel _model() => GenerativeModel(
        model: AppConfig.geminiModel,
        apiKey: AppConfig.geminiApiKey,
      );

  static Content userContent(String text) => Content.text(text);
  static Content modelContent(String text) => Content.model([TextPart(text)]);

  static Future<String?> generate(String prompt) async {
    final response = await _model().generateContent([Content.text(prompt)]);
    return response.text;
  }

  static Future<String?> extractTextFromImage(
    Uint8List imageBytes, {
    String prompt =
        'Extract all text from this exam paper image with 100% precision, '
        'preserving exact Bangla and English text formatting.',
  }) async {
    final response = await _model().generateContent([
      Content.multi([
        TextPart(prompt),
        DataPart('image/jpeg', imageBytes),
      ]),
    ]);
    return response.text;
  }

  static Future<String?> chat(List<Content> history, String message) async {
    final prompt = Content.text(message);
    final response = await _model().generateContent([...history, prompt]);
    return response.text;
  }
}
