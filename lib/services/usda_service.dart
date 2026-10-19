import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/food_item.dart';
import '../models/nutrition.dart';
import '../utils/usda_serving.dart';
import 'api_key_store.dart';

class UsdaService {
  static const String _baseUrl = 'https://api.nal.usda.gov/fdc/v1';

  static const Map<String, int> nutrientIds = {
    'calories': 1008,
    'protein': 1003,
    'carbs': 1005,
    'fat': 1004,
    'fiber': 1079,
    'sugar': 2000,
    'sodium': 1093,
    'sat_fat': 1258,
    'cholesterol': 1253,
    'potassium': 1092,
    'vit_a': 1106,
    'vit_c': 1162,
    'vit_d': 1114,
    'calcium': 1087,
    'iron': 1089,
  };

  Future<String> _getApiKey() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return '';

    String key = await ApiKeyStore.read(user.uid, 'usda');

    if (key.isEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('settings')
            .doc('config')
            .get();
        if (doc.exists && doc.data()?['usda_api_key'] != null) {
          key = doc.data()!['usda_api_key'].toString();
          await ApiKeyStore.write(user.uid, 'usda', key);
        }
      } catch (_) {}
    }
    return key;
  }

  Future<bool> _getIncludeBranded() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('usda_include_branded_${user.uid}') ?? false;
  }

  Future<List<Map<String, dynamic>>> searchFoods(String query) async {
    final apiKey = await _getApiKey();
    if (apiKey.isEmpty || query.trim().length < 2) return [];

    try {
      final includeBranded = await _getIncludeBranded();
      final dataTypes = includeBranded
          ? 'Foundation,SR%20Legacy,Branded'
          : 'Foundation,SR%20Legacy';

      final uri = Uri.parse(
        '$_baseUrl/foods/search?query=${Uri.encodeComponent(query)}&dataType=$dataTypes&requireAllWords=true&pageSize=15&api_key=$apiKey',
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return [];

      final data = json.decode(response.body);
      final List<dynamic> foods = data['foods'] ?? [];

      return foods
          .map(
            (f) => {
              'fdcId': f['fdcId'],
              'description': f['description'] ?? '',
              'brandOwner': f['brandOwner'] ?? '',
            },
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<FoodItem?> getFoodDetails(int fdcId) async {
    final apiKey = await _getApiKey();
    if (apiKey.isEmpty) return null;

    try {
      final uri = Uri.parse('$_baseUrl/food/$fdcId?api_key=$apiKey');
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final List<dynamic> nutrients = data['foodNutrients'] ?? [];

      double getNutrientAmount(int id) {
        for (final n in nutrients) {
          final nutrientInfo = n['nutrient'];
          if (nutrientInfo != null && nutrientInfo['id'] == id) {
            return (n['amount'] as num?)?.toDouble() ?? 0.0;
          }
        }
        return 0.0;
      }

      final isLiquid = isUsdaLiquid(data);
      final density = isLiquid ? usdaDensity(data) : 1.0;

      return FoodItem(
        id: '',
        name: data['description'] ?? 'USDA Food',
        source: 'usda',
        usdaFdcId: fdcId,
        servingSizeG: 100.0,
        baseUnit: isLiquid ? 'ml' : 'g',
        density: density,
        emoji: '🍽️',
        macros: MacroNutrients(
          calories: getNutrientAmount(nutrientIds['calories']!),
          proteinG: getNutrientAmount(nutrientIds['protein']!),
          carbsG: getNutrientAmount(nutrientIds['carbs']!),
          fatG: getNutrientAmount(nutrientIds['fat']!),
        ).scale(density), // USDA reports per 100g; liquids are displayed per 100ml.
        micros: MicroNutrients(
          fiberG: getNutrientAmount(nutrientIds['fiber']!),
          sugarG: getNutrientAmount(nutrientIds['sugar']!),
          sodiumMg: getNutrientAmount(nutrientIds['sodium']!),
          saturatedFatG: getNutrientAmount(nutrientIds['sat_fat']!),
          cholesterolMg: getNutrientAmount(nutrientIds['cholesterol']!),
          potassiumMg: getNutrientAmount(nutrientIds['potassium']!),
          vitaminAUg: getNutrientAmount(nutrientIds['vit_a']!),
          vitaminCMg: getNutrientAmount(nutrientIds['vit_c']!),
          vitaminDUg: getNutrientAmount(nutrientIds['vit_d']!),
          calciumMg: getNutrientAmount(nutrientIds['calcium']!),
          ironMg: getNutrientAmount(nutrientIds['iron']!),
        ).scale(density),
      );
    } catch (_) {
      return null;
    }
  }
}
