import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/food_item.dart';
import '../models/nutrition.dart';

enum AiAnalysisStatus {
  success,
  needsClarification,
  unrecognizable,
  rateLimited,
  unavailable,
  noKey,
  offline,
}

class AiAnalysisResult {
  final AiAnalysisStatus status;
  final FoodItem? foodItem;
  final double servings;
  final List<String> clarificationQuestions;
  final String? errorMessage;
  final String? modelUsed;

  const AiAnalysisResult({
    required this.status,
    this.foodItem,
    this.servings = 1.0,
    this.clarificationQuestions = const [],
    this.errorMessage,
    this.modelUsed,
  });
}

class GeminiService {
  static const List<String> _models = [
    'gemini-3.8-flash',
    'gemini-3.7-flash',
    'gemini-3.6-flash',
  ];

  static Future<String> getApiKey() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';

    final prefs = await SharedPreferences.getInstance();
    String key = prefs.getString('gemini_api_key_${user.uid}') ?? '';

    if (key.isEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('config')
            .get();
        if (doc.exists && doc.data()?['gemini_api_key'] != null) {
          key = doc.data()!['gemini_api_key'].toString();
          await prefs.setString('gemini_api_key_${user.uid}', key);
        }
      } catch (_) {}
    }
    return key;
  }

  static Future<String> fetchFoodEmoji(String foodName) async {
    final apiKey = await getApiKey();
    if (apiKey.isEmpty || foodName.trim().length < 2) return '🍽️';

    for (final model in _models) {
      try {
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
        );

        final response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'systemInstruction': {
                  'parts': [
                    {
                      'text':
                          'You are a food emoji assistant. Respond with EXACTLY ONE emoji and nothing else. Tunisian food names are highly accepted. If unrecognized, abstract, non-food, or gibberish, respond with 🍽️.'
                    }
                  ]
                },
                'contents': [
                  {
                    'parts': [
                      {'text': foodName}
                    ]
                  }
                ]
              }),
            )
            .timeout(const Duration(seconds: 15));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final candidates = data['candidates'] as List<dynamic>?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = candidates.first['content']?['parts'] as List<dynamic>? ?? [];
            for (final part in parts) {
              if (part is Map<String, dynamic> && part['thought'] != true && part.containsKey('text')) {
                final text = part['text'].toString().trim();
                final runes = text.runes.toList();
                if (runes.isNotEmpty) {
                  return String.fromCharCode(runes.first);
                }
              }
            }
          }
        }
      } on SocketException {
        return '🍽️';
      } catch (_) {
        continue;
      }
    }

    return '🍽️';
  }

  static Future<AiAnalysisResult> analyzeMealDescription({
    required String initialInput,
    String? followUpResponse,
    List<String>? previousQuestions,
  }) async {
    final apiKey = await getApiKey();
    if (apiKey.isEmpty) {
      return const AiAnalysisResult(
        status: AiAnalysisStatus.noKey,
        errorMessage: 'Gemini API key is required.',
      );
    }

    final isSecondTurn = (previousQuestions != null &&
        previousQuestions.isNotEmpty &&
        followUpResponse != null);

    final List<Map<String, dynamic>> contents = [];

    contents.add({
      'role': 'user',
      'parts': [{'text': initialInput}]
    });

    if (isSecondTurn) {
      contents.add({
        'role': 'model',
        'parts': [
          {
            'text': json.encode({
              'status': 'needs_clarification',
              'questions': previousQuestions,
            })
          }
        ]
      });
      contents.add({
        'role': 'user',
        'parts': [{'text': followUpResponse}]
      });
    }

    final String systemPrompt = '''
You are an expert clinical dietitian and nutritional database engine.
You parse meal descriptions (in English, French, Tunisian Derja / Franco-Arab, Arabic, or mixed) into precise nutritional estimates.

EVALUATION DECISION TREE:

1. IS IT GIBBERISH / NON-FOOD?
   - If the input contains NO recognizable food or drinks (e.g. random letters, greetings, or non-food objects):
     Return JSON:
     {
       "status": "unrecognizable",
       "reason": "No food detected"
     }

2. FIRST TURN EVALUATION (isSecondTurn = ${isSecondTurn}):
   - If this is TURN 1 AND the user mentions real food but omits key sizes, weights, or preparation methods:
     DO NOT GUESS ON TURN 1. You MUST return 1 to 3 brief clarifying questions in the user's EXACT language/dialect.
     Return JSON:
     {
       "status": "needs_clarification",
       "questions": [
         "1 to 3 brief, informative questions asking for portions, cooking methods (fried vs grilled), or main ingredients"
       ]
     }

3. SECOND TURN EVALUATION (isSecondTurn = ${isSecondTurn}):
   When the user responds to your questions on Turn 2:

   A. IF THE USER PROVIDED CLARIFYING DETAILS:
      Synthesize all details from Turn 1 + Turn 2 and return "status": "success".

   B. IF THE USER STILL DID NOT SPECIFY DETAILS / WAS VAGUE (e.g. "normal", "idk", "standard"):
      - Scenario B1 (Moderate/Standard Variance):
        If the food has a predictable single-serving profile (e.g., standard plate of pasta/couscous, kafteji, escalope, bowl of soup, sandwich, omelette):
        YOU ARE ALLOWED TO GUESS a standard conservative 1-person portion.
        Return "status": "success".

      - Scenario B2 (Critical / Catastrophic Variance):
        If the missing detail creates an extreme potential error margin (>3x-5x difference), such as:
        * Pizza (1 slice ~250 kcal vs whole pizza ~2,500 kcal)
        * Cake / Pastries (1 small bite vs whole cake)
        * Nuts / Dried Fruits / Oils / Butter without any container or scale benchmark
        * Bulk snacks / family-sized boxes without count or weight
        In this case, YOU MUST DISMISS THE REQUEST because guessing would produce completely invalid nutrition.
        Return JSON:
        {
          "status": "unrecognizable",
          "reason": "Portion variance is too large to estimate reliably without specified quantity."
        }

4. SUCCESS JSON FORMAT:
   {
     "status": "success",
     "food_name": "Brief concise meal name in input language (max 4 words)",
     "emoji": "Single most relevant food emoji",
     "servings": Number of servings or units consumed as a float (e.g. 1.0, 2.0, 3.0, 0.5),
     "serving_size_g": Base weight per ONE serving unit in grams (e.g. 50 for 1 egg, 100 for 1 slice, or total grams if 1 whole portion),
     "serving_name": "egg" / "slice" / "sandwich" / "cup" / "portion" / "bowl" / "plate",
     "base_unit": "g" or "ml",
     "macros": {
       "protein_g": total protein for the ENTIRE consumed meal,
       "carbs_g": total carbs for the ENTIRE consumed meal,
       "fat_g": total fat for the ENTIRE consumed meal
     },
     "micros": {
       "fiber_g": estimated or 0.0,
       "sugar_g": estimated or 0.0,
       "sodium_mg": estimated or 0.0,
       "saturated_fat_g": estimated or 0.0,
       "cholesterol_mg": estimated or 0.0,
       "potassium_mg": estimated or 0.0,
       "vitamin_a_ug": estimated or 0.0,
       "vitamin_c_mg": estimated or 0.0,
       "vitamin_d_ug": estimated or 0.0,
       "calcium_mg": estimated or 0.0,
       "iron_mg": estimated or 0.0
     }
   }

Always output valid JSON only. Do not wrap in markdown backticks or include thought tags.
''';

    bool wasRateLimited = false;

    for (final model in _models) {
      try {
        final uri = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
        );

        final response = await http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: json.encode({
                'systemInstruction': {
                  'parts': [{'text': systemPrompt}]
                },
                'contents': contents,
                'generationConfig': {
                  'temperature': 0.1,
                  'responseMimeType': 'application/json',
                }
              }),
            )
            .timeout(const Duration(seconds: 20));

        if (kDebugMode) {
          debugPrint('[Gemini AI] Model: $model | Status: ${response.statusCode}');
        }

        if (response.statusCode == 429) {
          wasRateLimited = true;
          continue;
        }

        if (response.statusCode != 200) {
          continue;
        }

        final data = json.decode(response.body);
        final candidates = data['candidates'] as List<dynamic>?;
        if (candidates == null || candidates.isEmpty) continue;

        final parts = candidates.first['content']?['parts'] as List<dynamic>? ?? [];
        String rawText = '';

        for (final part in parts) {
          if (part is Map<String, dynamic>) {
            if (part['thought'] == true) continue;
            if (part.containsKey('text')) {
              rawText += part['text'].toString();
            }
          }
        }

        if (rawText.isEmpty) {
          for (final part in parts) {
            if (part is Map<String, dynamic> && part.containsKey('text')) {
              final text = part['text'].toString();
              if (text.contains('{') && text.contains('}')) {
                rawText = text;
                break;
              }
            }
          }
        }

        final cleanJson = _extractCleanJson(rawText);
        if (cleanJson.isEmpty) continue;

        final parsed = json.decode(cleanJson) as Map<String, dynamic>;
        final statusStr = parsed['status']?.toString().toLowerCase();

        if (statusStr == 'needs_clarification' && !isSecondTurn) {
          final rawQuestions = parsed['questions'] as List<dynamic>? ?? [];
          final questions = rawQuestions.map((q) => q.toString()).where((q) => q.isNotEmpty).toList();

          if (questions.isNotEmpty) {
            return AiAnalysisResult(
              status: AiAnalysisStatus.needsClarification,
              clarificationQuestions: questions,
              modelUsed: model,
            );
          }
        }

        if (statusStr == 'success') {
          final macrosMap = parsed['macros'] as Map<String, dynamic>? ?? {};
          final microsMap = parsed['micros'] as Map<String, dynamic>? ?? {};

          final p = (macrosMap['protein_g'] as num?)?.toDouble() ?? 0.0;
          final c = (macrosMap['carbs_g'] as num?)?.toDouble() ?? 0.0;
          final f = (macrosMap['fat_g'] as num?)?.toDouble() ?? 0.0;
          final dynamicCalories = (p * 4.0) + (c * 4.0) + (f * 9.0);

          final servings = (parsed['servings'] as num?)?.toDouble() ?? 1.0;
          final baseServingG = (parsed['serving_size_g'] as num?)?.toDouble() ?? 100.0;

          final foodItem = FoodItem(
            id: '',
            name: parsed['food_name']?.toString() ?? 'Quick Log Food',
            source: 'custom',
            servingSizeG: baseServingG > 0 ? baseServingG : 100.0,
            baseUnit: parsed['base_unit']?.toString() ?? 'g',
            servingName: parsed['serving_name']?.toString() ?? 'portion',
            emoji: parsed['emoji']?.toString().isNotEmpty == true ? parsed['emoji'].toString() : '🍽️',
            macros: MacroNutrients(
              calories: dynamicCalories,
              proteinG: p,
              carbsG: c,
              fatG: f,
            ),
            micros: MicroNutrients(
              fiberG: (microsMap['fiber_g'] as num?)?.toDouble() ?? 0.0,
              sugarG: (microsMap['sugar_g'] as num?)?.toDouble() ?? 0.0,
              sodiumMg: (microsMap['sodium_mg'] as num?)?.toDouble() ?? 0.0,
              saturatedFatG: (microsMap['saturated_fat_g'] as num?)?.toDouble() ?? 0.0,
              cholesterolMg: (microsMap['cholesterol_mg'] as num?)?.toDouble() ?? 0.0,
              potassiumMg: (microsMap['potassium_mg'] as num?)?.toDouble() ?? 0.0,
              vitaminAUg: (microsMap['vitamin_a_ug'] as num?)?.toDouble() ?? 0.0,
              vitaminCMg: (microsMap['vitamin_c_mg'] as num?)?.toDouble() ?? 0.0,
              vitaminDUg: (microsMap['vitamin_d_ug'] as num?)?.toDouble() ?? 0.0,
              calciumMg: (microsMap['calcium_mg'] as num?)?.toDouble() ?? 0.0,
              ironMg: (microsMap['iron_mg'] as num?)?.toDouble() ?? 0.0,
            ),
          );

          return AiAnalysisResult(
            status: AiAnalysisStatus.success,
            foodItem: foodItem,
            servings: servings,
            modelUsed: model,
          );
        }

        return AiAnalysisResult(
          status: AiAnalysisStatus.unrecognizable,
          errorMessage: parsed['reason']?.toString() ?? 'Could not determine macros from your description.',
          modelUsed: model,
        );
      } on SocketException {
        return const AiAnalysisResult(
          status: AiAnalysisStatus.offline,
          errorMessage: 'No internet connection. Please check your network.',
        );
      } on TimeoutException {
        continue;
      } catch (_) {
        continue;
      }
    }

    if (wasRateLimited) {
      return const AiAnalysisResult(
        status: AiAnalysisStatus.rateLimited,
        errorMessage: 'AI is currently busy. Please try again in a moment.',
      );
    }

    return const AiAnalysisResult(
      status: AiAnalysisStatus.unavailable,
      errorMessage: 'AI is currently unavailable. Please try again later.',
    );
  }

  static String _extractCleanJson(String raw) {
    String text = raw.trim();
    text = text.replaceAll(RegExp(r'<thought>[\s\S]*?<\/thought>'), '').trim();

    if (text.startsWith('```')) {
      final lines = text.split('\n');
      if (lines.isNotEmpty && lines.first.startsWith('```')) {
        lines.removeAt(0);
      }
      if (lines.isNotEmpty && lines.last.startsWith('```')) {
        lines.removeLast();
      }
      text = lines.join('\n').trim();
    }

    final firstBrace = text.indexOf('{');
    final lastBrace = text.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace != -1 && lastBrace >= firstBrace) {
      return text.substring(firstBrace, lastBrace + 1).trim();
    }
    return '';
  }
}