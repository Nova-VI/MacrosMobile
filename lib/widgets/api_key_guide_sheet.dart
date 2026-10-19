import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

enum ApiKeyType { usda, gemini }

class ApiKeyGuideSheet extends StatefulWidget {
  final ApiKeyType initialService;

  const ApiKeyGuideSheet({
    super.key,
    this.initialService = ApiKeyType.usda,
  });

  static void show(BuildContext context, {ApiKeyType initialService = ApiKeyType.usda}) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ApiKeyGuideSheet(initialService: initialService),
    );
  }

  @override
  State<ApiKeyGuideSheet> createState() => _ApiKeyGuideSheetState();
}

class _ApiKeyGuideSheetState extends State<ApiKeyGuideSheet> {
  late ApiKeyType _selectedService;

  static const String _usdaUrl = 'https://fdc.nal.usda.gov/api-key-signup.html';
  static const String _geminiUrl = 'https://aistudio.google.com/app/apikey';

  @override
  void initState() {
    super.initState();
    _selectedService = widget.initialService;
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    HapticFeedback.mediumImpact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$label copied to clipboard',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        backgroundColor: AppColors.surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: AppColors.primary),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUsda = _selectedService == ApiKeyType.usda;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: AppColors.border),
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
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'API Key Setup Guide',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMain,
                  letterSpacing: -0.3,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: AppColors.textMuted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 12),

          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildServiceTab(
                    label: 'USDA FoodData',
                    type: ApiKeyType.usda,
                    icon: Icons.dataset_outlined,
                  ),
                ),
                Expanded(
                  child: _buildServiceTab(
                    label: 'Google Gemini',
                    type: ApiKeyType.gemini,
                    icon: Icons.auto_awesome_rounded,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Expanded(
            child: ListView(
              physics: const BouncingScrollPhysics(),
              children: isUsda ? _buildUsdaGuide() : _buildGeminiGuide(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceTab({
    required String label,
    required ApiKeyType type,
    required IconData icon,
  }) {
    final isSelected = _selectedService == type;

    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedService = type);
      },
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.surfaceHover : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primary.withValues(alpha: 0.5) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? AppColors.primary : AppColors.textMuted,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? AppColors.textMain : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildUsdaGuide() {
    return [
      _buildBenefitCard(
        title: 'USDA Food Database Access',
        description:
            'Enables instant search across 300,000+ verified foods, including complete macronutrients and 11 essential micronutrients.',
        color: AppColors.secondary,
      ),
      const SizedBox(height: 16),
      _buildStepItem(
        stepNumber: '1',
        title: 'Open the USDA API Key Portal',
        description: 'Navigate to the official FoodData Central API signup page in your web browser.',
        action: OutlinedButton.icon(
          onPressed: () => _copyToClipboard(_usdaUrl, 'USDA URL'),
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy Portal URL'),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.border),
            foregroundColor: AppColors.textMain,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      _buildStepItem(
        stepNumber: '2',
        title: 'Fill in Your Details',
        description:
            'Enter your First Name, Last Name, and Email Address. No credit card or payment is required; access is 100% free.',
      ),
      _buildStepItem(
        stepNumber: '3',
        title: 'Retrieve API Key from Email',
        description:
            'Check your inbox for an email from "api.data.gov". Copy the generated API key (a 40-character string).',
      ),
      _buildStepItem(
        stepNumber: '4',
        title: 'Paste into MacroTracker',
        description:
            'Return to MacroTracker and paste the key into the USDA API Access Key field, then tap "Save API Keys".',
      ),
    ];
  }

  List<Widget> _buildGeminiGuide() {
    return [
      _buildBenefitCard(
        title: 'Gemini AI Assistant',
        description:
            'Powers automatic emoji classification for your meals (including regional cuisines) and future intelligent nutrient insights.',
        color: AppColors.primary,
      ),
      const SizedBox(height: 16),
      _buildStepItem(
        stepNumber: '1',
        title: 'Open Google AI Studio',
        description: 'Navigate to Google AI Studio API key manager in your browser.',
        action: OutlinedButton.icon(
          onPressed: () => _copyToClipboard(_geminiUrl, 'Gemini URL'),
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy Studio URL'),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: AppColors.border),
            foregroundColor: AppColors.textMain,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
      _buildStepItem(
        stepNumber: '2',
        title: 'Sign in with Google',
        description: 'Log in using your existing Google account credentials and accept the terms of service. No credit card or payment is required; access is 100% free.',
      ),
      _buildStepItem(
        stepNumber: '3',
        title: 'Create an API Key',
        description:
            'Click on "Create API key" and select "Create key in new project" (or choose an existing project).',
      ),
      _buildStepItem(
        stepNumber: '4',
        title: 'Copy & Save Key',
        description:
            'Copy the generated key (starts with "AIzaSy..."), paste it into the Gemini AI Key field, and tap "Save API Keys".',
      ),
    ];
  }

  Widget _buildBenefitCard({
    required String title,
    required String description,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMain,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepItem({
    required String stepNumber,
    required String title,
    required String description,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.background,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
            ),
            alignment: Alignment.center,
            child: Text(
              stepNumber,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMain,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textMuted,
                    height: 1.35,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 8),
                  action,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}