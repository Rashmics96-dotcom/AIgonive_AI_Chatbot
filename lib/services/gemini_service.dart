import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';

class GeminiService {
  // ============================================================
  // API KEY
  // ============================================================

  // For local testing, the API key is supplied using --dart-define.
  //
  // Example:
  // flutter run -d chrome --dart-define=GEMINI_API_KEY=YOUR_API_KEY

  static const String apiKey =
  String.fromEnvironment('GEMINI_API_KEY');

  // ============================================================
  // MODEL
  // ============================================================

  static const String modelName = "gemini-3.6-flash";

  static final GenerativeModel model = GenerativeModel(
    model: modelName,
    apiKey: apiKey,
    generationConfig: GenerationConfig(
      maxOutputTokens: 2048,
    ),
  );

  // ============================================================
  // REQUEST CONTROL
  // ============================================================

  static DateTime? _lastRequestTime;

  static Future<void> _respectLocalRateLimit() async {
    final now = DateTime.now();

    if (_lastRequestTime != null) {
      final elapsed =
          now.difference(_lastRequestTime!).inMilliseconds;

      const int minimumGap = 3000;

      if (elapsed < minimumGap) {
        await Future.delayed(
          Duration(
            milliseconds: minimumGap - elapsed,
          ),
        );
      }
    }

    _lastRequestTime = DateTime.now();
  }

  // ============================================================
  // API KEY STATUS
  // ============================================================

  static bool get hasApiKey {
    return apiKey.trim().isNotEmpty;
  }

  // ============================================================
  // ERROR HANDLING
  // ============================================================

  static bool _isRateLimitError(String error) {
    final text = error.toLowerCase();

    return text.contains("429") ||
        text.contains("resource_exhausted") ||
        text.contains("quota exceeded") ||
        text.contains("rate limit") ||
        text.contains("too many requests");
  }

  static bool _isDailyQuotaError(String error) {
    final text = error.toLowerCase();

    return text.contains("requests per day") ||
        text.contains("daily quota") ||
        text.contains("rpd") ||
        text.contains("per-day");
  }

  static int _getRetrySeconds(String error) {
    final regex = RegExp(
      r'retry in\s+([0-9.]+)\s*s',
      caseSensitive: false,
    );

    final match = regex.firstMatch(error);

    if (match != null) {
      final value =
      double.tryParse(match.group(1)!);

      if (value != null) {
        final seconds = value.ceil();

        if (seconds < 1) {
          return 1;
        }

        if (seconds > 60) {
          return 60;
        }

        return seconds;
      }
    }

    return 5;
  }

  static String _friendlyError(Object error) {
    final text = error.toString();

    if (_isDailyQuotaError(text)) {
      return """
Gemini daily quota has been reached.

Your chatbot is working correctly, but the Gemini API project has reached its daily limit.

Please wait until the quota resets or use a project with higher API limits.

Model: $modelName
""";
    }

    if (_isRateLimitError(text)) {
      return """
Gemini API is temporarily rate-limited.

Please wait a few seconds and try again.

The app automatically retries temporary rate-limit errors.
""";
    }

    final lower = text.toLowerCase();

    if (lower.contains("api key") ||
        lower.contains("api_key") ||
        lower.contains("authentication")) {
      return """
Gemini API key is missing or invalid.

Start the app with:

flutter run -d chrome --dart-define=GEMINI_API_KEY=YOUR_API_KEY
""";
    }

    return "Sorry, something went wrong.\n\n$text";
  }

  // ============================================================
  // GENERATE CONTENT WITH RETRY
  // ============================================================

  static Future<GenerateContentResponse?> _generate(
      List<Content> content,
      ) async {
    if (!hasApiKey) {
      return null;
    }

    int attempt = 0;

    while (attempt < 3) {
      try {
        await _respectLocalRateLimit();

        final response =
        await model.generateContent(content);

        return response;
      } catch (e) {
        final error = e.toString();

        if (!_isRateLimitError(error)) {
          rethrow;
        }

        if (_isDailyQuotaError(error)) {
          rethrow;
        }

        attempt++;

        if (attempt >= 3) {
          rethrow;
        }

        final waitSeconds =
        _getRetrySeconds(error);

        await Future.delayed(
          Duration(
            seconds: waitSeconds,
          ),
        );
      }
    }

    return null;
  }

  // ============================================================
  // NORMAL AI CHAT
  // ============================================================

  static Future<String> askAI(
      String prompt, {
        List<Map<String, dynamic>> history = const [],
      }) async {
    try {
      if (!hasApiKey) {
        return """
Gemini API key is not configured.

Start the app using:

flutter run -d chrome --dart-define=GEMINI_API_KEY=YOUR_API_KEY
""";
      }

      final List<Content> conversation = [];

      // Previous conversation
      for (final message in history) {
        final bool isUser =
            message["isUser"] == true;

        final String text =
        (message["text"] ?? "").toString();

        if (text.trim().isEmpty) {
          continue;
        }

        conversation.add(
          Content(
            isUser ? "user" : "model",
            [
              TextPart(text),
            ],
          ),
        );
      }

      // Current user question
      conversation.add(
        Content.text(prompt),
      );

      final response =
      await _generate(conversation);

      if (response == null) {
        return "No response received.";
      }

      return response.text ??
          "No response received.";
    } catch (e) {
      return _friendlyError(e);
    }
  }

  // ============================================================
  // IMAGE CHAT
  // ============================================================

  static Future<String> askImage(
      Uint8List imageBytes,
      String prompt, {
        String mimeType = "image/jpeg",
        List<Map<String, dynamic>> history = const [],
      }) async {
    try {
      if (!hasApiKey) {
        return """
Gemini API key is not configured.

Start the app using:

flutter run -d chrome --dart-define=GEMINI_API_KEY=YOUR_API_KEY
""";
      }

      final List<Content> conversation = [];

      // Previous text conversation
      for (final message in history) {
        final bool isUser =
            message["isUser"] == true;

        final String text =
        (message["text"] ?? "").toString();

        if (text.trim().isEmpty) {
          continue;
        }

        conversation.add(
          Content(
            isUser ? "user" : "model",
            [
              TextPart(text),
            ],
          ),
        );
      }

      // Current image + question
      conversation.add(
        Content.multi(
          [
            TextPart(
              """
You are an AI Study Assistant.

The user has uploaded an image.

Answer the user's question specifically about the uploaded image.

User question:
$prompt
""",
            ),
            DataPart(
              mimeType,
              imageBytes,
            ),
          ],
        ),
      );

      final response =
      await _generate(conversation);

      if (response == null) {
        return "No response received.";
      }

      return response.text ??
          "No response received.";
    } catch (e) {
      return _friendlyError(e);
    }
  }
}