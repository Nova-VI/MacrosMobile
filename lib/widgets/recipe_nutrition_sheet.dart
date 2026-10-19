import 'package:flutter/material.dart';
import '../models/nutrition.dart';
import '../theme/app_theme.dart';

class RecipeNutritionSheet extends StatelessWidget {
  final MacroNutrients macros;
  final MicroNutrients micros;
  final double totalGrams;

  const RecipeNutritionSheet({
    super.key,
    required this.macros,
    required this.micros,
    required this.totalGrams,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recipe Nutrition Facts',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textMain),
                  ),
                  Text(
                    'Total Yield: ${totalGrams.round()}g',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: AppColors.textMuted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: [
                _buildFactRow('Calories', '${macros.calories.round()} kcal', isBold: true, color: AppColors.primary),
                _buildFactRow('Protein', '${macros.proteinG.toStringAsFixed(1)}g', isBold: true),
                _buildFactRow('Carbohydrates', '${macros.carbsG.toStringAsFixed(1)}g', isBold: true),
                _buildFactRow('Fat', '${macros.fatG.toStringAsFixed(1)}g', isBold: true),
                const Divider(color: AppColors.border, height: 24),
                _buildFactRow('Fiber', '${micros.fiberG.toStringAsFixed(1)}g'),
                _buildFactRow('Sugar', '${micros.sugarG.toStringAsFixed(1)}g'),
                _buildFactRow('Sodium', '${micros.sodiumMg.round()}mg'),
                _buildFactRow('Saturated Fat', '${micros.saturatedFatG.toStringAsFixed(1)}g'),
                _buildFactRow('Cholesterol', '${micros.cholesterolMg.round()}mg'),
                _buildFactRow('Potassium', '${micros.potassiumMg.round()}mg'),
                _buildFactRow('Vitamin A', '${micros.vitaminAUg.round()}µg'),
                _buildFactRow('Vitamin C', '${micros.vitaminCMg.toStringAsFixed(1)}mg'),
                _buildFactRow('Vitamin D', '${micros.vitaminDUg.toStringAsFixed(1)}µg'),
                _buildFactRow('Calcium', '${micros.calciumMg.round()}mg'),
                _buildFactRow('Iron', '${micros.ironMg.toStringAsFixed(1)}mg'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFactRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w500,
              color: isBold ? AppColors.textMain : AppColors.textMuted,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w700,
              color: color ?? AppColors.textMain,
            ),
          ),
        ],
      ),
    );
  }
}