import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text_styles.dart';

/// A premium horizontal step-progress indicator: a connecting line with
/// numbered circles on top and a label under each step. Used by multi-step
/// flows like the Post Property wizard.
class StepIndicator extends StatelessWidget {
  final int currentStep;
  final List<String> stepLabels;

  const StepIndicator({
    super.key,
    required this.currentStep,
    required this.stepLabels,
  });

  static const double _circleDiameter = 34;
  static const double _lineThickness = 3;

  @override
  Widget build(BuildContext context) {
    final stepCount = stepLabels.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = constraints.maxWidth / stepCount;
        final lineTop = (_circleDiameter - _lineThickness) / 2;
        final progressFraction = stepCount > 1
            ? currentStep / (stepCount - 1)
            : 0.0;
        final trackWidth = constraints.maxWidth - slotWidth;

        return SizedBox(
          height: 78,
          child: Stack(
            children: [
              Positioned(
                top: lineTop,
                left: slotWidth / 2,
                width: trackWidth,
                child: Container(
                  height: _lineThickness,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(_lineThickness),
                  ),
                ),
              ),
              Positioned(
                top: lineTop,
                left: slotWidth / 2,
                width: trackWidth * progressFraction,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutCubic,
                  height: _lineThickness,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(_lineThickness),
                  ),
                ),
              ),
              Row(
                children: List.generate(stepCount, (index) {
                  final isActive = index == currentStep;
                  final isCompleted = index < currentStep;
                  final isHighlighted = isActive || isCompleted;

                  return SizedBox(
                    width: slotWidth,
                    child: Column(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          width: _circleDiameter,
                          height: _circleDiameter,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: isHighlighted
                                ? AppColors.primaryGradient
                                : null,
                            color: isHighlighted ? null : Colors.white,
                            border: Border.all(
                              color: isHighlighted
                                  ? AppColors.primary
                                  : Colors.grey.shade300,
                              width: 1.5,
                            ),
                            boxShadow: isActive ? AppColors.primaryGlow : null,
                          ),
                          child: Center(
                            child: isCompleted
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 18,
                                  )
                                : Text(
                                    '${index + 1}',
                                    style: AppTextStyles.caption.copyWith(
                                      color: isActive
                                          ? Colors.white
                                          : AppColors.textSecondary,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          stepLabels[index],
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption.copyWith(
                            color: isActive
                                ? AppColors.textPrimary
                                : AppColors.textSecondary,
                            fontWeight: isActive
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ],
          ),
        );
      },
    );
  }
}
