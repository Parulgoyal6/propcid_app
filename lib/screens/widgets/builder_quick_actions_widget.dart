import 'package:flutter/material.dart';

class BuilderQuickActionsWidget extends StatelessWidget {
  const BuilderQuickActionsWidget({super.key});

  Widget actionButton(
    BuildContext context,
    IconData icon,
    String title,
    Color accent,
    VoidCallback onTap,
  ) {
    final scheme = Theme.of(context).colorScheme;

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          splashColor: accent.withOpacity(0.12),
          highlightColor: accent.withOpacity(0.06),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: scheme.outline.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: scheme.shadow.withOpacity(0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 8),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        accent.withOpacity(0.20),
                        accent.withOpacity(0.08),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Icon(icon, size: 24, color: accent),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            actionButton(
              context,
              Icons.add_business_rounded,
              "Add Project",
              scheme.primary,
              () {},
            ),
            const SizedBox(width: 12),
            actionButton(
              context,
              Icons.analytics_rounded,
              "Analytics",
              Colors.teal,
              () {},
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            actionButton(
              context,
              Icons.people_rounded,
              "Network",
              Colors.brown,
              () {},
            ),
            const SizedBox(width: 12),
            actionButton(
              context,
              Icons.question_answer_rounded,
              "Enquiries",
              Colors.deepOrange,
              () {},
            ),
          ],
        ),
      ],
    );
  }
}
