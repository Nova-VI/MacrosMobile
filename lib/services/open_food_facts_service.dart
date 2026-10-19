import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/food_item.dart';
import '../models/nutrition.dart';
import '../utils/open_food_facts_serving.dart';

enum OpenFoodFactsStatus { success, unreliableData, notFound, offline, error }

class OpenFoodFactsResult {
  final OpenFoodFactsStatus status;
  final FoodItem? foodItem;
  final String? message;

  const OpenFoodFactsResult({
    required this.status,
    this.foodItem,
    this.message,
  });
}

class OpenFoodFactsService {
  static const String _baseUrl = 'https://world.openfoodfacts.org/api/v2';

  Future<OpenFoodFactsResult> getProductByBarcode(String barcode) async {
    final cleanCode = barcode.trim();
    if (cleanCode.isEmpty) {
      return const OpenFoodFactsResult(
        status: OpenFoodFactsStatus.notFound,
        message: 'Invalid barcode.',
      );
    }

    try {
      final uri = Uri.parse(
        '$_baseUrl/product/$cleanCode.json?fields=product_name,product_name_en,generic_name,brands,serving_size,serving_quantity,serving_quantity_unit,nutriments,quantity',
      );

      final response = await http
          .get(
            uri,
            headers: {'User-Agent': 'MacroTracker - Mobile - Version 1.0.0'},
          )
          .timeout(const Duration(seconds: 7));

      if (response.statusCode != 200) {
        return const OpenFoodFactsResult(
          status: OpenFoodFactsStatus.notFound,
          message: 'Product not found in database.',
        );
      }

      final data = json.decode(response.body);
      final status = data['status'];
      if (status != 1 || data['product'] == null) {
        return const OpenFoodFactsResult(
          status: OpenFoodFactsStatus.notFound,
          message: 'Product not found in database.',
        );
      }

      final product = data['product'] as Map<String, dynamic>;
      final nutriments = product['nutriments'] as Map<String, dynamic>? ?? {};

      // 1. Resolve Food Name
      String name =
          product['product_name']?.toString().trim() ??
          product['product_name_en']?.toString().trim() ??
          product['generic_name']?.toString().trim() ??
          '';

      final brand = product['brands']?.toString().trim() ?? '';
      if (brand.isNotEmpty &&
          !name.toLowerCase().contains(brand.toLowerCase())) {
        name = name.isNotEmpty ? '$brand $name' : brand;
      }
      if (name.isEmpty) {
        name = 'Scanned Product ($cleanCode)';
      }

      // 2. Parse Serving Size and Unit
      final quantityUnit =
          product['serving_quantity_unit']?.toString().trim().toLowerCase() ??
          '';
      final rawServingSize = product['serving_size']?.toString().trim() ?? '';
      final servingG = openFoodFactsServingAmount(
        product['serving_quantity'],
        quantityUnit,
        rawServingSize,
      );
      final servingName = rawServingSize;

      final nameLower = name.toLowerCase();
      final isLiquid =
          nameLower.contains('milk') ||
          nameLower.contains('lait') ||
          nameLower.contains('juice') ||
          nameLower.contains('jus') ||
          nameLower.contains('water') ||
          nameLower.contains('eau') ||
          nameLower.contains('boisson') ||
          nameLower.contains('drink') ||
          nameLower.contains('beverage') ||
          nameLower.contains('soda') ||
          nameLower.contains('huile') ||
          nameLower.contains('oil') ||
          rawServingSize.toLowerCase().contains('ml') ||
          ['ml', 'cl', 'l', 'fl oz'].contains(quantityUnit);

      final baseUnit = isLiquid ? 'ml' : 'g';

      // 3. Helper to parse nutrients per 100g
      double getNutrimentPer100g(
        String key, [
        List<String> altKeys = const [],
      ]) {
        if (nutriments.containsKey('${key}_100g')) {
          return (nutriments['${key}_100g'] as num?)?.toDouble() ?? 0.0;
        }
        if (nutriments.containsKey(key)) {
          return (nutriments[key] as num?)?.toDouble() ?? 0.0;
        }
        for (final alt in altKeys) {
          if (nutriments.containsKey('${alt}_100g')) {
            return (nutriments['${alt}_100g'] as num?)?.toDouble() ?? 0.0;
          }
          if (nutriments.containsKey(alt)) {
            return (nutriments[alt] as num?)?.toDouble() ?? 0.0;
          }
        }
        return 0.0;
      }

      final ratio = servingG / 100.0;

      final double p100 = getNutrimentPer100g('proteins', ['protein']);
      final double c100 = getNutrimentPer100g('carbohydrates', ['carbs']);
      final double f100 = getNutrimentPer100g('fat', ['lipids']);

      // 4. Quality check: if all macros are 0, mark as unreliable
      if (p100 == 0.0 && c100 == 0.0 && f100 == 0.0) {
        final incompleteItem = FoodItem(
          id: '',
          name: name,
          source: 'openfoodfacts',
          servingSizeG: servingG,
          baseUnit: baseUnit,
          servingName: servingName,
          emoji: '🍽️',
          macros: const MacroNutrients(),
          micros: const MicroNutrients(),
        );

        return OpenFoodFactsResult(
          status: OpenFoodFactsStatus.unreliableData,
          foodItem: incompleteItem,
          message:
              'Nutrition facts are missing for this product on Open Food Facts.',
        );
      }

      // 5. Scale to parsed base serving and calculate calories on the fly
      final double baseProtein = p100 * ratio;
      final double baseCarbs = c100 * ratio;
      final double baseFat = f100 * ratio;
      final double calculatedCalories =
          (baseProtein * 4.0) + (baseCarbs * 4.0) + (baseFat * 9.0);

      final fiber = getNutrimentPer100g('fiber') * ratio;
      final sugar = getNutrimentPer100g('sugars', ['sugar']) * ratio;
      final satFat = getNutrimentPer100g('saturated-fat') * ratio;

      double sodiumMg = getNutrimentPer100g('sodium') * 1000.0 * ratio;
      if (sodiumMg <= 0) {
        final saltG = getNutrimentPer100g('salt') * ratio;
        if (saltG > 0) sodiumMg = saltG * 400.0;
      }

      final cholesterolMg = getNutrimentPer100g('cholesterol') * 1000.0 * ratio;
      final potassiumMg = getNutrimentPer100g('potassium') * 1000.0 * ratio;
      final calciumMg = getNutrimentPer100g('calcium') * 1000.0 * ratio;
      final ironMg = getNutrimentPer100g('iron') * 1000.0 * ratio;
      final vitCMg = getNutrimentPer100g('vitamin-c') * 1000.0 * ratio;
      final vitAUg = getNutrimentPer100g('vitamin-a') * 1000000.0 * ratio;
      final vitDUg = getNutrimentPer100g('vitamin-d') * 1000000.0 * ratio;

      final foodItem = FoodItem(
        id: '',
        name: name,
        source: 'openfoodfacts',
        servingSizeG: servingG,
        baseUnit: baseUnit,
        servingName: servingName,
        emoji: '🍽️',
        macros: MacroNutrients(
          calories: calculatedCalories,
          proteinG: baseProtein,
          carbsG: baseCarbs,
          fatG: baseFat,
        ),
        micros: MicroNutrients(
          fiberG: fiber,
          sugarG: sugar,
          sodiumMg: sodiumMg,
          saturatedFatG: satFat,
          cholesterolMg: cholesterolMg,
          potassiumMg: potassiumMg,
          vitaminAUg: vitAUg,
          vitaminCMg: vitCMg,
          vitaminDUg: vitDUg,
          calciumMg: calciumMg,
          ironMg: ironMg,
        ),
      );

      return OpenFoodFactsResult(
        status: OpenFoodFactsStatus.success,
        foodItem: foodItem,
      );
    } on SocketException {
      return const OpenFoodFactsResult(
        status: OpenFoodFactsStatus.offline,
        message: 'No internet connection. Please check your network.',
      );
    } on TimeoutException {
      return const OpenFoodFactsResult(
        status: OpenFoodFactsStatus.offline,
        message: 'Connection timed out. Please check your network.',
      );
    } on http.ClientException {
      return const OpenFoodFactsResult(
        status: OpenFoodFactsStatus.offline,
        message: 'Unable to reach the network.',
      );
    } catch (e) {
      return OpenFoodFactsResult(
        status: OpenFoodFactsStatus.error,
        message: 'Lookup failed: ${e.toString()}',
      );
    }
  }
}
