import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/food_item.dart';
import '../services/open_food_facts_service.dart';
import '../theme/app_theme.dart';

typedef FoodScanFoundCallback =
    void Function(FoodItem food, {bool isUnreliable});
typedef FoodScanNotFoundCallback = void Function(String message);

class BarcodeScannerSheet extends StatefulWidget {
  final FoodScanFoundCallback onFoodFound;
  final FoodScanNotFoundCallback? onNotFound;

  const BarcodeScannerSheet({
    super.key,
    required this.onFoodFound,
    this.onNotFound,
  });

  static Future<void> show(
    BuildContext context, {
    required FoodScanFoundCallback onFoodFound,
    FoodScanNotFoundCallback? onNotFound,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          BarcodeScannerSheet(onFoodFound: onFoodFound, onNotFound: onNotFound),
    );
  }

  @override
  State<BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<BarcodeScannerSheet>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _scannerController;
  late final AnimationController _scanAnimationController;
  final OpenFoodFactsService _offService = OpenFoodFactsService();

  bool _isProcessing = false;
  bool _isTorchOn = false;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    _scanAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanAnimationController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _handleBarcodeDetected(String barcode) async {
    if (_isProcessing || !mounted) return;
    setState(() => _isProcessing = true);
    HapticFeedback.heavyImpact();

    final result = await _offService.getProductByBarcode(barcode);

    if (!mounted) return;

    if (result.status == OpenFoodFactsStatus.success &&
        result.foodItem != null) {
      HapticFeedback.mediumImpact();
      Navigator.pop(context);
      widget.onFoodFound(result.foodItem!, isUnreliable: false);
      return;
    }

    if (result.status == OpenFoodFactsStatus.unreliableData &&
        result.foodItem != null) {
      HapticFeedback.mediumImpact();
      Navigator.pop(context);
      widget.onFoodFound(result.foodItem!, isUnreliable: true);
      return;
    }

    if (result.status == OpenFoodFactsStatus.offline) {
      HapticFeedback.lightImpact();
      Navigator.pop(context);
      widget.onNotFound?.call(
        result.message ?? 'No internet connection. Please check your network.',
      );
      return;
    }

    if (!mounted) return;

    HapticFeedback.lightImpact();
    Navigator.pop(context);
    widget.onNotFound?.call(
      result.message ?? 'Product not found for barcode "$barcode".',
    );
  }

  void _showManualBarcodeDialog() {
    final textCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text(
          'Enter Barcode Manually',
          style: TextStyle(
            color: AppColors.textMain,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          style: const TextStyle(
            color: AppColors.textMain,
            fontWeight: FontWeight.w700,
          ),
          decoration: const InputDecoration(
            labelText: 'Barcode digits',
            hintText: 'e.g. 6191234567890',
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.border),
                    foregroundColor: AppColors.textMain,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    final code = textCtrl.text.trim();
                    if (code.isNotEmpty) {
                      Navigator.pop(ctx);
                      _handleBarcodeDetected(code);
                    }
                  },
                  child: const Text(
                    'Lookup',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(color: AppColors.border),
      ),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            child: MobileScanner(
              controller: _scannerController,
              onDetect: (capture) {
                final barcodes = capture.barcodes;
                for (final b in barcodes) {
                  final raw = b.rawValue;
                  if (raw != null && raw.isNotEmpty) {
                    _handleBarcodeDetected(raw);
                    break;
                  }
                }
              },
            ),
          ),
          Center(
            child: Container(
              width: 260,
              height: 200,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.primary, width: 2.5),
              ),
              child: AnimatedBuilder(
                animation: _scanAnimationController,
                builder: (context, child) {
                  return Align(
                    alignment: Alignment(
                      0.0,
                      (_scanAnimationController.value * 2) - 1.0,
                    ),
                    child: Container(
                      height: 2,
                      width: 240,
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.8),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.2),
                      ),
                    ),
                    child: const Text(
                      'Scan Barcode / QR',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(
                        _isTorchOn
                            ? Icons.flash_on_rounded
                            : Icons.flash_off_rounded,
                        color: _isTorchOn ? AppColors.primary : Colors.white,
                        size: 22,
                      ),
                      onPressed: () async {
                        HapticFeedback.selectionClick();
                        await _scannerController.toggleTorch();
                        setState(() => _isTorchOn = !_isTorchOn);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 30,
            left: 20,
            right: 20,
            child: Column(
              children: [
                if (_isProcessing)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primary),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Looking up nutrition data...',
                          style: TextStyle(
                            color: AppColors.textMain,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                OutlinedButton.icon(
                  onPressed: _showManualBarcodeDialog,
                  icon: const Icon(Icons.keyboard_alt_outlined, size: 18),
                  label: const Text(
                    'Enter Barcode Manually',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                    foregroundColor: Colors.white,
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
