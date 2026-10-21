// Focused tests for InAppUpdateService's branching logic — driven by a fake
// UpdateCheckClient, since the real one is a platform channel to Google Play
// and cannot be exercised here. Each test resets the static session gate
// (resetSessionGateForTest) unless it's specifically testing that gate.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/services/in_app_update_service.dart';
import 'package:propcid_app/services/update_check_client.dart';

class _FakeUpdateCheckClient implements UpdateCheckClient {
  _FakeUpdateCheckClient({
    this.checkResult,
    this.checkError,
    this.runOutcome = FlexibleUpdateOutcome.downloaded,
    this.runError,
  });

  final UpdateCheckResult? checkResult;
  final Object? checkError;
  final FlexibleUpdateOutcome runOutcome;
  final Object? runError;

  int checkCalls = 0;
  int runCalls = 0;
  int completeCalls = 0;

  @override
  Future<UpdateCheckResult> checkForUpdate() async {
    checkCalls++;
    if (checkError != null) throw checkError!;
    return checkResult!;
  }

  @override
  Future<FlexibleUpdateOutcome> runFlexibleUpdate() async {
    runCalls++;
    if (runError != null) throw runError!;
    return runOutcome;
  }

  @override
  Future<void> completeFlexibleUpdate() async {
    completeCalls++;
  }
}

Future<BuildContext> _pumpContext(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    ),
  );
  return captured;
}

void main() {
  setUp(() {
    InAppUpdateService.resetSessionGateForTest();
  });

  testWidgets('non-Android platforms never call the update client', (
    tester,
  ) async {
    final client = _FakeUpdateCheckClient(
      checkResult: const UpdateCheckResult(
        updateAvailable: true,
        flexibleAllowed: true,
      ),
    );
    final context = await _pumpContext(tester);

    await InAppUpdateService.checkOnce(
      context,
      service: InAppUpdateService(client: client, isAndroid: () => false),
    );

    expect(client.checkCalls, 0);
  });

  testWidgets('no update available does not start a flexible update', (
    tester,
  ) async {
    final client = _FakeUpdateCheckClient(
      checkResult: const UpdateCheckResult(
        updateAvailable: false,
        flexibleAllowed: false,
      ),
    );
    final context = await _pumpContext(tester);

    await InAppUpdateService.checkOnce(
      context,
      service: InAppUpdateService(client: client, isAndroid: () => true),
    );

    expect(client.checkCalls, 1);
    expect(client.runCalls, 0);
  });

  testWidgets(
    'an update that is not flexible-allowed does not start a flexible update',
    (tester) async {
      final client = _FakeUpdateCheckClient(
        checkResult: const UpdateCheckResult(
          updateAvailable: true,
          flexibleAllowed: false,
        ),
      );
      final context = await _pumpContext(tester);

      await InAppUpdateService.checkOnce(
        context,
        service: InAppUpdateService(client: client, isAndroid: () => true),
      );

      expect(client.runCalls, 0);
    },
  );

  testWidgets(
    'checkForUpdate throwing (flutter run / no Play Store / offline) is swallowed',
    (tester) async {
      final client = _FakeUpdateCheckClient(
        checkError: Exception('Play Services unavailable'),
      );
      final context = await _pumpContext(tester);

      await InAppUpdateService.checkOnce(
        context,
        service: InAppUpdateService(client: client, isAndroid: () => true),
      );

      expect(client.runCalls, 0);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'runFlexibleUpdate throwing (unexpected platform error) is swallowed, no prompt',
    (tester) async {
      final client = _FakeUpdateCheckClient(
        checkResult: const UpdateCheckResult(
          updateAvailable: true,
          flexibleAllowed: true,
        ),
        runError: Exception('IN_APP_UPDATE_FAILED'),
      );
      final context = await _pumpContext(tester);

      await InAppUpdateService.checkOnce(
        context,
        service: InAppUpdateService(client: client, isAndroid: () => true),
      );

      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('a declined/failed/cancelled flexible update shows no prompt', (
    tester,
  ) async {
    final client = _FakeUpdateCheckClient(
      checkResult: const UpdateCheckResult(
        updateAvailable: true,
        flexibleAllowed: true,
      ),
      runOutcome: FlexibleUpdateOutcome.declinedOrFailed,
    );
    final context = await _pumpContext(tester);

    await InAppUpdateService.checkOnce(
      context,
      service: InAppUpdateService(client: client, isAndroid: () => true),
    );

    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'a successful download shows the restart prompt, and Restart now completes the update',
    (tester) async {
      final client = _FakeUpdateCheckClient(
        checkResult: const UpdateCheckResult(
          updateAvailable: true,
          flexibleAllowed: true,
        ),
        runOutcome: FlexibleUpdateOutcome.downloaded,
      );
      final context = await _pumpContext(tester);

      await InAppUpdateService.checkOnce(
        context,
        service: InAppUpdateService(client: client, isAndroid: () => true),
      );
      await tester.pumpAndSettle();

      expect(find.text('Update ready'), findsOneWidget);
      expect(
        find.text(
          'A new version of PropCID is ready. Restart to complete the update.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Restart now'));
      await tester.pumpAndSettle();

      expect(client.completeCalls, 1);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets('tapping Later dismisses without completing the update', (
    tester,
  ) async {
    final client = _FakeUpdateCheckClient(
      checkResult: const UpdateCheckResult(
        updateAvailable: true,
        flexibleAllowed: true,
      ),
      runOutcome: FlexibleUpdateOutcome.downloaded,
    );
    final context = await _pumpContext(tester);

    await InAppUpdateService.checkOnce(
      context,
      service: InAppUpdateService(client: client, isAndroid: () => true),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Later'));
    await tester.pumpAndSettle();

    expect(client.completeCalls, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets(
    'a second checkOnce call in the same session never calls the client again',
    (tester) async {
      final client = _FakeUpdateCheckClient(
        checkResult: const UpdateCheckResult(
          updateAvailable: false,
          flexibleAllowed: false,
        ),
      );
      final context = await _pumpContext(tester);
      final service = InAppUpdateService(client: client, isAndroid: () => true);

      await InAppUpdateService.checkOnce(context, service: service);
      await InAppUpdateService.checkOnce(context, service: service);

      expect(client.checkCalls, 1);
    },
  );
}
