import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/food_item.dart';
import '../services/gemini_service.dart';
import '../theme/app_theme.dart';

typedef AiMealParsedCallback = void Function(FoodItem food);
typedef AiMealErrorCallback = void Function(String message);

class AiMealPromptSheet extends StatefulWidget {
  final AiMealParsedCallback onMealParsed;
  final AiMealErrorCallback onError;

  const AiMealPromptSheet({
    super.key,
    required this.onMealParsed,
    required this.onError,
  });

  static Future<void> show(
    BuildContext context, {
    required AiMealParsedCallback onMealParsed,
    required AiMealErrorCallback onError,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiMealPromptSheet(
        onMealParsed: onMealParsed,
        onError: onError,
      ),
    );
  }

  @override
  State<AiMealPromptSheet> createState() => _AiMealPromptSheetState();
}

class _AiMealPromptSheetState extends State<AiMealPromptSheet> {
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _clarificationController = TextEditingController();

  bool _isProcessing = false;
  bool _isClarificationMode = false;
  String _initialPromptCache = '';
  List<String> _activeQuestions = [];

  @override
  void dispose() {
    _inputController.dispose();
    _clarificationController.dispose();
    super.dispose();
  }

  Future<void> _submitInitialPrompt() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _isProcessing = true;
      _initialPromptCache = text;
    });

    final result = await GeminiService.analyzeMealDescription(
      initialInput: text,
    );

    if (!mounted) return;

    _handleAnalysisResult(result);
  }

  Future<void> _submitClarification() async {
    final followUp = _clarificationController.text.trim();
    if (followUp.isEmpty) return;

    FocusScope.of(context).unfocus();
    setState(() => _isProcessing = true);

    final result = await GeminiService.analyzeMealDescription(
      initialInput: _initialPromptCache,
      previousQuestions: _activeQuestions,
      followUpResponse: followUp,
    );

    if (!mounted) return;

    _handleAnalysisResult(result);
  }

  void _handleAnalysisResult(AiAnalysisResult result) {
    if (result.status == AiAnalysisStatus.success && result.foodItem != null) {
      HapticFeedback.mediumImpact();
      Navigator.pop(context);
      widget.onMealParsed(result.foodItem!);
      return;
    }

    if (result.status == AiAnalysisStatus.needsClarification &&
        result.clarificationQuestions.isNotEmpty &&
        !_isClarificationMode) {
      HapticFeedback.selectionClick();
      setState(() {
        _isProcessing = false;
        _isClarificationMode = true;
        _activeQuestions = result.clarificationQuestions;
      });
      return;
    }

    // Abort and report error immediately
    HapticFeedback.lightImpact();
    Navigator.pop(context);

    String message;
    switch (result.status) {
      case AiAnalysisStatus.rateLimited:
        message = 'AI is busy. Please try again in a moment.';
        break;
      case AiAnalysisStatus.offline:
        message = 'No internet connection. Please check your network.';
        break;
      case AiAnalysisStatus.noKey:
        message = 'Gemini API key is required in Profile Settings.';
        break;
      case AiAnalysisStatus.unrecognizable:
        message = 'Could not determine macros from your description.';
        break;
      case AiAnalysisStatus.unavailable:
      default:
        message = result.errorMessage ?? 'AI is currently unavailable.';
        break;
    }

    widget.onError(message);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _isClarificationMode ? 'Meal Clarification' : 'Describe Your Meal',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textMain,
                      letterSpacing: -0.3,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (!_isClarificationMode) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Include specific ingredients, cooking methods, and weights for accurate macros.',
                      style: TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.35),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _inputController,
              autofocus: true,
              enabled: !_isProcessing,
              maxLines: 4,
              minLines: 3,
              style: const TextStyle(color: AppColors.textMain, fontSize: 14),
              decoration: InputDecoration(
                hintText:
                    'e.g., 200g grilled turkey escalope with 150g cooked pasta and 1 tbsp olive oil...',
                fillColor: AppColors.background,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _submitInitialPrompt,
              icon: _isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome_rounded, size: 18),
              label: Text(_isProcessing ? 'Analyzing Meal...' : 'Analyze Meal'),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.help_outline_rounded, color: AppColors.warning, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'A few quick details are needed:',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textMain,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._activeQuestions.map(
                    (q) => Padding(
                      padding: const EdgeInsets.only(left: 6, bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ', style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold)),
                          Expanded(
                            child: Text(
                              q,
                              style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _clarificationController,
              autofocus: true,
              enabled: !_isProcessing,
              maxLines: 3,
              style: const TextStyle(color: AppColors.textMain, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Answer the above questions briefly...',
                fillColor: AppColors.background,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isProcessing ? null : _submitClarification,
              child: _isProcessing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Calculate Nutrition'),
            ),
          ],
        ],
      ),
    );
  }
}