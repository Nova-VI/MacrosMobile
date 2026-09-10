import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GeminiService {
  static const List<String> _models = [
    'gemini-3.8-flash',
    'gemini-3.7-flash',
    'gemini-3.6-flash',
  ];

  static Future<String> _getApiKey() async {
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
    final apiKey = await _getApiKey();
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
            .timeout(const Duration(seconds: 4));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          final candidates = data['candidates'] as List<dynamic>?;
          if (candidates != null && candidates.isNotEmpty) {
            final parts = candidates.first['content']?['parts'] as List<dynamic>?;
            if (parts != null && parts.isNotEmpty) {
              final text = parts.first['text']?.toString().trim() ?? '';
              final runes = text.runes.toList();
              if (runes.isNotEmpty) {
                return String.fromCharCode(runes.first);
              }
            }
          }
        }
      } catch (_) {}
    }

    return '🍽️';
  }
}