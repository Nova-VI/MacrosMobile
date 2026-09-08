import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

class EmojiPickerSheet extends StatelessWidget {
  final ValueChanged<String> onEmojiSelected;

  const EmojiPickerSheet({
    super.key,
    required this.onEmojiSelected,
  });

  static const List<Map<String, dynamic>> categories = [
    {
      'name': 'Common',
      'emojis': ['🍽️', '🍲', '🥣', '🥗', '🥪', '🥩', '🍗', '🍔', '🍕', '🍣']
    },
    {
      'name': 'Fruits',
      'emojis': ['🍏', '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🍈', '🍒', '🍑', '🥭', '🍍', '🥥', '🥝', '🍅']
    },
    {
      'name': 'Vegetables',
      'emojis': ['🍆', '🥑', '🥦', '🥬', '🥒', '🌶️', '🫑', '🌽', '🥕', '🫒', '🧄', '🧅', '🥔', '🍠']
    },
    {
      'name': 'Meat & Protein',
      'emojis': ['🥩', '🍗', '🍖', '🥓', '🐟', '🍤', '🦐', '🦀', '🥚', '🍳', '🧀', '🧈', '🥛']
    },
    {
      'name': 'Meals & Grains',
      'emojis': ['🍞', '🥐', '🥖', '🥞', '🧇', '🍟', '🍕', '🥪', '🌮', '🌯', '🍝', '🍜', '🍲', '🍛', '🍚', '🥟']
    },
    {
      'name': 'Sweets & Snacks',
      'emojis': ['🍦', '🍩', '🍪', '🎂', '🍰', '🍫', '🍬', '🍭', '🍮', '🍯', '🍿', '🥜']
    },
    {
      'name': 'Drinks',
      'emojis': ['☕', '🍵', '🧃', '🥤', '🧋', '🥛', '🍼', '🍷', '🍺', '🍻', '🍹']
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.58,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      decoration: const BoxDecoration(
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
          const Text(
            'Select Food Icon',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textMain),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              physics: const BouncingScrollPhysics(),
              itemCount: categories.length,
              itemBuilder: (context, idx) {
                final cat = categories[idx];
                final List<String> emojis = cat['emojis'];

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        cat['name'].toString().toUpperCase(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textMuted, letterSpacing: 0.5),
                      ),
                    ),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 6,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: emojis.length,
                      itemBuilder: (context, eIdx) {
                        return InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            onEmojiSelected(emojis[eIdx]);
                            Navigator.pop(context);
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border.withValues(alpha: 0.5)),
                            ),
                            alignment: Alignment.center,
                            child: Text(emojis[eIdx], style: const TextStyle(fontSize: 22)),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}