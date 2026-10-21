// Verification harness for the Phase 1 SearchBarWidget fix.
//
// Every test below pumps under the REAL AppTheme.lightTheme, because the
// double-border defect originated in that theme's `inputDecorationTheme`
// (filled: true + a focused 2 dp primary OutlineInputBorder at r14). Pumping
// with a default theme would pass trivially and prove nothing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/theme/app_colors.dart';
import 'package:propcid_app/core/theme/app_theme.dart';
import 'package:propcid_app/widgets/search_bar_widget.dart';

const Key _kMicKey = Key('mic-badge');

/// Stand-in for the 38x38 gradient mic badge. Both real call sites (the Search
/// Entry screen and Home's PremiumSearchSection) pass a badge of exactly this
/// size, so the bar's inset arithmetic is what's under test here.
Widget _micBadge() => Container(
      key: _kMicKey,
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(13),
      ),
    );

Widget _harness(Widget child) => MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: child,
          ),
        ),
      ),
    );

/// The bar's own outer Container.
BoxDecoration _barDecoration(WidgetTester tester) {
  final container = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(SearchBarWidget),
          matching: find.byType(Container),
        )
        .first,
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  group('Search Entry bar (editable, focused)', () {
    late FocusNode focusNode;
    late TextEditingController controller;

    setUp(() {
      focusNode = FocusNode();
      controller = TextEditingController();
    });

    tearDown(() {
      focusNode.dispose();
      controller.dispose();
    });

    Future<void> pumpEntryBar(WidgetTester tester) async {
      await tester.pumpWidget(_harness(SearchBarWidget(
        hint: 'Try "3BHK villa under 1 crore in Dehradun"',
        onTap: null,
        controller: controller,
        focusNode: focusNode,
        height: 54,
        borderRadius: 18,
        boxShadow: AppColors.surfaceCardShadow,
        leadingPadding: 16,
        trailingPadding: 8,
        iconGap: 10,
        trailingGap: 10,
        trailing: _micBadge(),
      )));
      // Focus reproduces the exact condition that surfaced the defect: the
      // Search Entry screen calls requestFocus() in initState.
      focusNode.requestFocus();
      await tester.pumpAndSettle();
    }

    testWidgets('1. no double border — every border slot is none, no fill',
        (tester) async {
      await pumpEntryBar(tester);
      expect(focusNode.hasFocus, isTrue, reason: 'defect only shows focused');

      final decoration = tester.widget<TextField>(find.byType(TextField)).decoration!;

      expect(decoration.border, InputBorder.none);
      expect(decoration.enabledBorder, InputBorder.none);
      expect(decoration.focusedBorder, InputBorder.none);
      expect(decoration.disabledBorder, InputBorder.none);
      expect(decoration.errorBorder, InputBorder.none);
      expect(decoration.focusedErrorBorder, InputBorder.none);
      expect(decoration.filled, isFalse);

      // The real proof: after AppTheme's InputDecorationTheme defaults are
      // merged in, NOTHING survives that could paint a second border or fill.
      final effective =
          decoration.applyDefaults(AppTheme.lightTheme.inputDecorationTheme);
      expect(effective.border, InputBorder.none);
      expect(effective.enabledBorder, InputBorder.none);
      expect(effective.focusedBorder, InputBorder.none,
          reason: 'theme focusedBorder (2dp primary @ r14) must not leak');
      expect(effective.filled, isFalse,
          reason: 'theme filled:true must not paint an inner r14 surface');

      // The bar's container is therefore the only visible surface.
      final bar = _barDecoration(tester);
      expect(bar.borderRadius, BorderRadius.circular(18));
      expect(bar.color, AppColors.cardBackground);
      expect(bar.border, isNull);
    });

    testWidgets('2. text is vertically centred in the 54dp bar',
        (tester) async {
      await pumpEntryBar(tester);

      final barRect = tester.getRect(find.byType(SearchBarWidget));
      final textRect = tester.getRect(find.byType(EditableText));

      expect(barRect.height, 54);
      expect(
        textRect.center.dy,
        closeTo(barRect.center.dy, 0.5),
        reason: 'text centre must sit on the bar centre',
      );

      // The leading icon centres too, so icon and text share a baseline band.
      final iconRect = tester.getRect(find.byIcon(Icons.search));
      expect(iconRect.center.dy, closeTo(barRect.center.dy, 0.5));
    });

    testWidgets('3. mic is inset on all sides — visually integrated',
        (tester) async {
      await pumpEntryBar(tester);

      final barRect = tester.getRect(find.byType(SearchBarWidget));
      final micRect = tester.getRect(find.byKey(_kMicKey));
      final iconRect = tester.getRect(find.byIcon(Icons.search));

      expect(micRect.size, const Size(38, 38));

      // 54 - 38 = 16, split evenly => 8dp above and below.
      expect(micRect.top - barRect.top, closeTo(8, 0.5));
      expect(barRect.bottom - micRect.bottom, closeTo(8, 0.5));
      // trailingPadding: 8 (redesign spec `padding: 0 8px 0 16px`).
      expect(barRect.right - micRect.right, closeTo(8, 0.5));
      // Inset on all four sides, so it reads as inside the bar.
      expect(micRect.left - barRect.left, greaterThan(8));

      // leadingPadding: 16.
      expect(iconRect.left - barRect.left, closeTo(16, 0.5));
      // Mic sits fully within the bar's bounds.
      expect(barRect.contains(micRect.topLeft), isTrue);
      expect(barRect.contains(micRect.bottomRight - const Offset(0.1, 0.1)),
          isTrue);
    });
  });

  group('Home bar (read-only, no optional params) is unchanged', () {
    Future<void> pumpHomeBar(WidgetTester tester) async {
      // Replicates PremiumSearchSection's call site exactly: an onTap handler
      // and a 38dp trailing badge, and NONE of the new optional parameters.
      await tester.pumpWidget(_harness(SearchBarWidget(
        hint: 'Search properties, locations...',
        onTap: () {},
        trailing: _micBadge(),
      )));
      await tester.pumpAndSettle();
    }

    testWidgets('4a. keeps 48dp height and 14dp radius', (tester) async {
      await pumpHomeBar(tester);

      expect(tester.getRect(find.byType(SearchBarWidget)).height, 48);
      expect(_barDecoration(tester).borderRadius, BorderRadius.circular(14));
    });

    testWidgets('4b. takes the read-only branch — never builds a TextField',
        (tester) async {
      await pumpHomeBar(tester);

      // This is why every InputDecoration change above is unreachable for Home.
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(EditableText), findsNothing);
      expect(find.text('Search properties, locations...'), findsOneWidget);
    });

    testWidgets('4c. keeps its original 12/8/0/12 gutters', (tester) async {
      await pumpHomeBar(tester);

      final barRect = tester.getRect(find.byType(SearchBarWidget));
      final iconRect = tester.getRect(find.byIcon(Icons.search));
      final micRect = tester.getRect(find.byKey(_kMicKey));

      // leadingPadding default 12.
      expect(iconRect.left - barRect.left, closeTo(12, 0.5));
      // trailingPadding default 12.
      expect(barRect.right - micRect.right, closeTo(12, 0.5));
      // 48 - 38 = 10, split evenly => 5dp above and below (unchanged).
      expect(micRect.top - barRect.top, closeTo(5, 0.5));

      // iconGap default 8: the hint text starts 8dp after the 18dp icon.
      final textRect = tester.getRect(find.text('Search properties, locations...'));
      expect(textRect.left - iconRect.right, closeTo(8, 0.5));
    });
  });
}
