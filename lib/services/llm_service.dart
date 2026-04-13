import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Sends a base64 image + spoken question to the GPT-4o Vision API
/// and returns the model's natural-language description.
class LlmService {
  final String _apiKey;
  final String _model;

  /// System prompt designed for visually impaired users.
  /// Clear, concise, practical descriptions — no poetic language.
  static const String _systemPrompt = '''
You are a visual assistant for blind and visually impaired users. 
The user is pointing their phone camera at something and asking a question about it.

Rules:
- Describe what you see clearly, concisely, and in plain language.
- Answer the user's specific question first, then add relevant context.
- If reading text (labels, signs, screens), read it exactly as written.
- For safety-related questions (is the stove on, is the road clear), prioritize accuracy and err on the side of caution.
- Keep answers to 2-3 sentences unless the user asks for more detail.
- If the image is too dark, blurry, or unclear, say so honestly and suggest adjusting the camera.
- Never say "I see an image of..." — just describe what's there directly.
- Use specific details: "a white mug with a blue handle" not "a cup".
- For currency, read the denomination clearly.
- For medicine bottles, read the drug name and dosage.
''';

  LlmService({
    required String apiKey,
    String model = 'gpt-4o',
  })  : _apiKey = apiKey,
        _model = model;

  /// Send a question + image to GPT-4o and get a spoken-friendly answer.
  ///
  /// [question] — the user's transcribed speech
  /// [imageBase64] — JPEG image encoded as base64
  ///
  /// Returns the model's text response, or an error message.
  Future<String> askAboutImage({
    required String question,
    required String imageBase64,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'max_tokens': 300,
          'messages': [
            {
              'role': 'system',
              'content': _systemPrompt,
            },
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': question,
                },
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/jpeg;base64,$imageBase64',
                    'detail': 'low', // faster + cheaper; 'high' for fine print
                  },
                },
              ],
            },
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final answer = data['choices'][0]['message']['content'] as String;
        debugPrint('[LLM] Response: $answer');
        return answer;
      } else {
        final error = jsonDecode(response.body);
        final msg = error['error']?['message'] ?? 'Unknown API error';
        debugPrint('[LLM] API error ${response.statusCode}: $msg');
        return 'Sorry, I had trouble connecting to the AI service. Please try again.';
      }
    } catch (e) {
      debugPrint('[LLM] Request failed: $e');
      return 'Sorry, I could not reach the server. Check your internet connection.';
    }
  }

  /// Simpler text-only query (no image) for follow-up questions.
  Future<String> askTextOnly({required String question}) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_apiKey',
        },
        body: jsonEncode({
          'model': _model,
          'max_tokens': 300,
          'messages': [
            {'role': 'system', 'content': _systemPrompt},
            {'role': 'user', 'content': question},
          ],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'] as String;
      } else {
        return 'Sorry, I had trouble processing that. Please try again.';
      }
    } catch (e) {
      return 'Sorry, I could not reach the server. Check your internet connection.';
    }
  }
}