import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'portal_icon.dart';
import 'portal_theme.dart';

/// Form primitives reproduced from the portal's wizard-wide CSS
/// (`.property-wizard-container` in PropertyWizard.tsx) plus its shadcn Card /
/// Label / Input components.
///
/// Steps 2-8 build from these rather than from `wizard_kit.dart`, which
/// implements the app's own (indigo, rounded, shadowed) design language.

/// A shadcn `Card` as the wizard renders it: white, 1px slate border,
/// `rounded-xl`, no elevation of its own.
class PortalCard extends StatelessWidget {
  const PortalCard({super.key, this.title, this.icon, required this.child});

  /// Rendered as the `card-header` when present (14px per the CSS override).
  final String? title;
  final IconData? icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: PortalTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PortalTheme.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Padding(
              // `[class*="card-header"] { padding: 8px 12px }`
              padding: PortalTheme.cardHeaderPadding,
              child: Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 16, color: PortalTheme.accent),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      title!,
                      // `.card-title { font-size: 14px }`
                      style: PortalTheme.inputLabel.copyWith(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: PortalTheme.titleText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: PortalTheme.slate100),
          ],
          Padding(
            // `[class*="card-content"] { padding: 10px 12px }`
            padding: PortalTheme.cardContentPadding,
            child: child,
          ),
        ],
      ),
    );
  }
}

/// A labelled field. The portal renders `<Label>` above the control with a 2px
/// gap, and marks required fields with a literal ` *` in the label text.
class PortalField extends StatelessWidget {
  const PortalField({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
    this.helper,
  });

  final String label;
  final Widget child;
  final bool required;

  /// Small grey note under a control — the portal uses `text-[11px]
  /// text-slate-500` for these.
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            text: label,
            style: PortalTheme.inputLabel,
            children: required
                ? const [
                    TextSpan(
                      text: ' *',
                      style: TextStyle(color: PortalTheme.fieldLabel),
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 2), // label { margin-bottom: 2px }
        child,
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(helper!, style: PortalTheme.helperText),
        ],
      ],
    );
  }
}

/// Text input matching the portal: 14px text, 34px tall, 1px slate border,
/// `rounded-md`. Turns red when [hasError], per the wizard's
/// `[data-field-error="true"]` rule.
class PortalTextField extends StatelessWidget {
  const PortalTextField({
    super.key,
    required this.controller,
    this.hint,
    this.onChanged,
    this.keyboardType,
    this.maxLines = 1,
    this.hasError = false,
    this.prefix,
    this.suffix,
    this.inputFormatters,
  });

  final TextEditingController controller;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final int maxLines;
  final bool hasError;

  /// The portal strips characters in `onChange` — e.g. area inputs run
  /// `value.replace(/[^\d.]/g, '')`. A formatter is the Flutter equivalent and
  /// keeps the caret stable, which rewriting the controller would not.
  final List<TextInputFormatter>? inputFormatters;

  /// e.g. the leading rupee glyph the portal puts inside amount inputs.
  final Widget? prefix;

  /// e.g. a trailing unit label (`"sq ft"`) shown inline inside the field.
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    final single = maxLines == 1;
    return Container(
      // textarea { min-height: 60px }, input { height: 34px }
      height: single ? PortalTheme.inputHeight : null,
      constraints: single ? null : const BoxConstraints(minHeight: 60),
      decoration: BoxDecoration(
        color: PortalTheme.cardSurface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasError ? PortalTheme.fieldError : PortalTheme.cardBorder,
          width: hasError ? 1.5 : 1,
        ),
        boxShadow: hasError
            ? [
                BoxShadow(
                  color: PortalTheme.fieldError.withValues(alpha: 0.18),
                  blurRadius: 0,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      alignment: single ? Alignment.centerLeft : Alignment.topLeft,
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: single ? 0 : 6),
      child: Row(
        crossAxisAlignment: single
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          if (prefix != null) ...[prefix!, const SizedBox(width: 4)],
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              keyboardType: keyboardType,
              inputFormatters: inputFormatters,
              maxLines: maxLines,
              // Leaving this unset lets the platform decide these fields are
              // autofillable (a browser's or Android's own heuristic based on
              // the field's neighbouring label/hint) and draw its own
              // highlight/outline over them while focused — outside this
              // widget's own painting, and the source of the "blue border"
              // some fields showed while typing. None of these portal-ported
              // fields (headline, plot no., mauja, tehsil, ...) are things a
              // platform autofill service should ever be suggesting values
              // for, so it's turned off explicitly here rather than left to
              // guesswork.
              autofillHints: const [],
              style: PortalTheme.inputText,
              decoration: InputDecoration(
                isDense: true,
                // The app-wide `ThemeData.inputDecorationTheme`
                // (app_theme.dart) sets its own `focusedBorder` (a blue,
                // 2px, radius-14 OutlineInputBorder) as a default for every
                // text field. `border:` only fills that one named slot —
                // `enabledBorder`/`focusedBorder`/`disabledBorder`/
                // `errorBorder`/`focusedErrorBorder` are separate slots that
                // `InputDecoration.applyDefaults` fills from the theme
                // independently when left unset, regardless of what
                // `border:` says. Leaving them unset let that theme default
                // paint its blue outline over this field's own outer
                // `Container` border the moment it gained focus — the actual
                // "double border" this was. Setting every slot to
                // `InputBorder.none` here means this inner `TextField` never
                // draws a border in any state, so the outer `Container`'s
                // single border (drawn above) is the only one ever visible.
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: hint,
                hintStyle: PortalTheme.inputText.copyWith(
                  color: PortalTheme.radioIdle,
                ),
              ),
            ),
          ),
          if (suffix != null) ...[const SizedBox(width: 4), suffix!],
        ],
      ),
    );
  }
}

/// Error banner shown at the top of a step — reproduction of
/// `components/common/ValidationSummary.tsx`.
class PortalValidationSummary extends StatelessWidget {
  const PortalValidationSummary({
    super.key,
    required this.messages,
    this.title = 'Please complete these fields before continuing',
  });

  final List<String> messages;
  final String title;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 12), // mb-3
      padding: const EdgeInsets.all(12), // p-3
      decoration: BoxDecoration(
        color: PortalTheme.errorSurface, // bg-red-50
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(color: PortalTheme.errorBorder), // border-red-200
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: PortalIcon(
              'alert-circle',
              size: 16,
              color: PortalTheme.errorIcon,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title (${messages.length})',
                  style: PortalTheme.errorTitle,
                ),
                const SizedBox(height: 6), // mt-1.5
                // `flex flex-wrap gap-x-3 gap-y-1` of dotted-underlined items
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    for (final m in messages)
                      Text(m, style: PortalTheme.errorItem),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `StepHeader` — the tinted card each step opens with.
/// Portal geometry (`shadow-sm`, `rounded-2xl`, p-4, mb-5); the tint is the
/// app's primary, where the portal used orange-50/100.
class PortalStepHeader extends StatelessWidget {
  const PortalStepHeader({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badge,
    this.badge2,
  });

  final String icon;
  final String title;
  final String subtitle;

  /// Right-hand pill — the portal passes `listingType.toUpperCase()`.
  final String? badge;

  /// Left-hand pill — `propertyType.toUpperCase()`. Rendered FIRST.
  final String? badge2;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20), // mb-5
      padding: const EdgeInsets.all(16), // p-4
      decoration: BoxDecoration(
        color: PortalTheme.cardSurface,
        borderRadius: BorderRadius.circular(16), // rounded-2xl
        border: Border.all(color: PortalTheme.headerBorder),
        boxShadow: PortalTheme.cardShadow, // shadow-sm
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: PortalTheme.headerSurface,
              borderRadius: BorderRadius.circular(12), // rounded-xl
            ),
            child: Center(
              child: PortalIcon(icon, size: 20, color: PortalTheme.accent),
            ),
          ),
          const SizedBox(width: 12), // gap-3
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    Text(title, style: PortalTheme.stepHeaderTitle),
                    if (badge2 != null)
                      _PortalPill(
                        badge2!,
                        bg: PortalTheme.slate100,
                        fg: PortalTheme.slate600,
                      ),
                    if (badge != null)
                      _PortalPill(
                        badge!,
                        bg: PortalTheme.headerSurface,
                        fg: PortalTheme.accent,
                      ),
                  ],
                ),
                const SizedBox(height: 4), // mb-1
                Text(subtitle, style: PortalTheme.stepHeaderSubtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PortalPill extends StatelessWidget {
  const _PortalPill(this.text, {required this.bg, required this.fg});

  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(text.toUpperCase(), style: PortalTheme.pill(fg)),
  );
}

/// `SectionDivider` — icon tile, 13px bold title, hairline filling the rest.
class PortalSectionDivider extends StatelessWidget {
  const PortalSectionDivider({
    super.key,
    required this.icon,
    required this.title,
    this.iconBg,
    this.iconColor,
  });

  final String icon;
  final String title;
  final Color? iconBg;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16), // mb-4
    child: Row(
      children: [
        Container(
          width: 28, // w-7
          height: 28,
          decoration: BoxDecoration(
            color: iconBg ?? PortalTheme.headerBorder,
            borderRadius: BorderRadius.circular(8), // rounded-lg
          ),
          child: Center(
            child: PortalIcon(
              icon,
              size: 16,
              color: iconColor ?? PortalTheme.accent,
            ),
          ),
        ),
        const SizedBox(width: 12), // gap-3
        // Flexible, not fixed: the portal renders this on a wide desktop
        // column where the title always fits. On a phone a longer heading
        // ("Builder Project (Optional)") overruns the row, so the title
        // yields space to the trailing hairline rather than overflowing.
        // The heading is never truncated.
        Flexible(child: Text(title, style: PortalTheme.sectionDividerTitle)),
        const SizedBox(width: 12),
        Expanded(child: Divider(height: 1, color: PortalTheme.slate200)),
      ],
    ),
  );
}

/// A `<Select>` as the portal renders it: a 34px trigger showing the value or
/// its placeholder, opening a sheet of options. [groups] reproduces
/// `SelectGroup` + `SelectLabel` (used for residential subtypes).
class PortalSelect extends StatelessWidget {
  const PortalSelect({
    super.key,
    required this.value,
    required this.placeholder,
    required this.onChanged,
    this.options = const [],
    this.groups,
    this.hasError = false,
    this.labelFor,
    this.triggerWidth,
  });

  final String? value;
  final String placeholder;
  final List<String> options;
  final List<(String, List<String>)>? groups;
  final ValueChanged<String> onChanged;
  final bool hasError;

  /// Maps a `SelectItem` value to its display text, for the selects whose
  /// value and label differ — area units are `sq_ft` / "Square Feet".
  /// Identity when null.
  final String Function(String value)? labelFor;

  /// `SelectTrigger className="w-32"` etc. Full width when null.
  final double? triggerWidth;

  Future<void> _open(BuildContext context) async {
    final entries = groups ?? [('', options)];
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final entry in entries) ...[
              if (entry.$1.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(
                    entry.$1.toUpperCase(),
                    style: PortalTheme.selectGroupLabel,
                  ),
                ),
              for (final o in entry.$2)
                ListTile(
                  dense: true,
                  title: Text(
                    labelFor?.call(o) ?? o,
                    style: PortalTheme.inputText,
                  ),
                  trailing: o == value
                      ? const PortalIcon(
                          'check',
                          size: 16,
                          color: PortalTheme.accent,
                        )
                      : null,
                  onTap: () => Navigator.of(ctx).pop(o),
                ),
            ],
          ],
        ),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final empty = value == null || value!.isEmpty;
    return GestureDetector(
      onTap: () => _open(context),
      child: Container(
        height: PortalTheme.inputHeight,
        width: triggerWidth,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: PortalTheme.cardSurface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: hasError ? PortalTheme.fieldError : PortalTheme.cardBorder,
            width: hasError ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                empty ? placeholder : (labelFor?.call(value!) ?? value!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: empty
                    ? PortalTheme.inputText.copyWith(
                        color: PortalTheme.radioIdle,
                      )
                    : PortalTheme.inputText,
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: PortalTheme.slate400,
            ),
          ],
        ),
      ),
    );
  }
}

/// An input-prefix icon, as the portal absolutely-positions inside its inputs
/// (`absolute left-3 top-1/2 w-4 h-4 text-<colour>-500`).
class PortalIconTint extends StatelessWidget {
  const PortalIconTint(this.name, {super.key, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      PortalIcon(name, size: 16, color: color);
}

/// A field whose `<Label>` carries a small coloured lucide icon —
/// `<Label className="flex items-center gap-1.5"><Icon .../>Text *</Label>`.
class PortalLabelledField extends StatelessWidget {
  const PortalLabelledField({
    super.key,
    required this.label,
    required this.child,
    this.icon,
    this.iconColor,
    this.required = false,
    this.helper,
  });

  final String label;
  final Widget child;
  final String? icon;
  final Color? iconColor;
  final bool required;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              PortalIcon(icon!, size: 14, color: iconColor), // w-3.5 h-3.5
              const SizedBox(width: 6), // gap-1.5
            ],
            Flexible(
              child: Text(
                required ? '$label *' : label,
                style: PortalTheme.inputLabel,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        child,
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(helper!, style: PortalTheme.helperText),
        ],
      ],
    );
  }
}

/// [PortalLabelledField] wrapping a [PortalSelect] — the portal's most common
/// pairing on this step.
class PortalLabelledSelect extends StatelessWidget {
  const PortalLabelledSelect({
    super.key,
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onChanged,
    this.options = const [],
    this.groups,
    this.icon,
    this.iconColor,
    this.required = false,
  });

  final String label;
  final String? value;
  final String placeholder;
  final ValueChanged<String> onChanged;
  final List<String> options;
  final List<(String, List<String>)>? groups;
  final String? icon;
  final Color? iconColor;
  final bool required;

  @override
  Widget build(BuildContext context) => PortalLabelledField(
    label: label,
    icon: icon,
    iconColor: iconColor,
    required: required,
    child: PortalSelect(
      value: value,
      placeholder: placeholder,
      options: options,
      groups: groups,
      onChanged: onChanged,
    ),
  );
}

/// A bare `<h4 className="text-lg font-semibold tracking-tight">` block heading
/// in its `mb-2 mt-4 pt-3` wrapper, optionally followed by a
/// `<p className="text-sm text-muted-foreground">` line.
///
/// PropertyDimensionsStep uses this — not [PortalSectionDivider] — to open
/// "Land Specfication", "Building Level Details", "Area Details",
/// "PG Structure & Capacity" and the two inventory blocks.
class PortalBlockHeading extends StatelessWidget {
  const PortalBlockHeading(this.title, {super.key, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Padding(
    // mt-4 pt-3 = 28 above, mb-2 = 8 below
    padding: const EdgeInsets.only(top: 28, bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: PortalTheme.blockHeading),
        if (subtitle != null) Text(subtitle!, style: PortalTheme.blockSubtitle),
      ],
    ),
  );
}

/// `components/ui/checkbox.tsx` — `h-4 w-4 rounded-sm border border-primary`,
/// filling with `bg-primary` and a white `Check` when set, beside its
/// `font-normal cursor-pointer` label.
class PortalCheckbox extends StatelessWidget {
  const PortalCheckbox({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  /// The app's primary, not the portal's shadcn `--primary`.
  static const Color _primary = PortalTheme.accent;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => onChanged(!value),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: value ? _primary : Colors.transparent,
            borderRadius: BorderRadius.circular(2), // rounded-sm
            border: Border.all(color: _primary),
          ),
          child: value
              ? const Center(
                  child: PortalIcon('check', size: 12, color: Colors.white),
                )
              : null,
        ),
        const SizedBox(width: 8), // space-x-2
        Text(
          label,
          style: PortalTheme.inputLabel.copyWith(fontWeight: FontWeight.w400),
        ),
      ],
    ),
  );
}

/// A non-editable value box styled like an input —
/// `flex items-center h-10 px-3 rounded-md border-2 border-gray-300`.
/// The portal uses it for PG "Total Rooms", which is derived, not typed.
class PortalReadOnlyBox extends StatelessWidget {
  const PortalReadOnlyBox(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    height: PortalTheme.inputHeight,
    alignment: Alignment.centerLeft,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: PortalTheme.cardSurface,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: PortalTheme.cardBorder),
    ),
    child: Text(
      text,
      style: PortalTheme.inputText.copyWith(fontWeight: FontWeight.w500),
    ),
  );
}
