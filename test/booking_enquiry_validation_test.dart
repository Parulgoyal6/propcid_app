// Pins the Schedule Visit / Enquiry sheets' validation and error-mapping
// rules — `BookVisitModal.tsx:112-130,344-350` transcribed into
// `VisitFormValidation`, plus the [StateError]-vs-generic-error split in
// `describeSubmitError`. Pure functions; no widget, no Supabase client.
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/screens/property_detail/booking_enquiry_validation.dart';

void main() {
  group('VisitFormValidation.nameError', () {
    test('empty name is required', () {
      expect(VisitFormValidation.nameError(''), 'Name is required');
      expect(VisitFormValidation.nameError('   '), 'Name is required');
    });

    test('digits or symbols are rejected', () {
      expect(
        VisitFormValidation.nameError('Asha123'),
        'Name should only contain alphabets',
      );
    });

    test('a plain alphabetic name (with spaces) is accepted', () {
      expect(VisitFormValidation.nameError('Asha Rao'), isNull);
    });
  });

  group('VisitFormValidation.phoneError', () {
    test('empty phone is required', () {
      expect(VisitFormValidation.phoneError(''), 'Phone number required');
    });

    test('fewer than 10 digits is rejected', () {
      expect(
        VisitFormValidation.phoneError('98765'),
        'Enter valid 10 digit mobile number',
      );
    });

    test('a 10-digit phone is accepted', () {
      expect(VisitFormValidation.phoneError('9876543210'), isNull);
    });
  });

  group('VisitFormValidation.isSlotDisabled', () {
    test('never disabled for a future date, regardless of the hour', () {
      final future = DateTime(2026, 9, 10);
      final now = DateTime(2026, 9, 9, 23);
      expect(VisitFormValidation.isSlotDisabled('10:00', future, now), isFalse);
    });

    test('a slot is disabled for today once its real (PM-aware) hour has passed', () {
      final today = DateTime(2026, 9, 9);
      final now = DateTime(2026, 9, 9, 14, 30); // 2:30 PM
      // "02:00" means 2 PM (14:00) here, not 2 AM — it has passed by 2:30 PM.
      expect(VisitFormValidation.isSlotDisabled('02:00', today, now), isTrue);
      // "04:00" means 4 PM (16:00) — still ahead of 2:30 PM.
      expect(VisitFormValidation.isSlotDisabled('04:00', today, now), isFalse);
    });

    test('morning slots (10:00, 11:00) and noon are not treated as PM', () {
      final today = DateTime(2026, 9, 9);
      final now = DateTime(2026, 9, 9, 10, 30); // 10:30 AM
      expect(VisitFormValidation.isSlotDisabled('10:00', today, now), isTrue);
      expect(VisitFormValidation.isSlotDisabled('11:00', today, now), isFalse);
      expect(VisitFormValidation.isSlotDisabled('12:00', today, now), isFalse);
      // Every afternoon slot is still ahead of 10:30 AM.
      expect(VisitFormValidation.isSlotDisabled('06:00', today, now), isFalse);
    });

    test('every slot stays selectable in the evening after 6 PM only if the date rolls over', () {
      // The old literal-label comparison disabled every slot once it was
      // past noon; this is the regression it was fixed for.
      final today = DateTime(2026, 9, 9);
      final lateAfternoon = DateTime(2026, 9, 9, 17, 0); // 5 PM
      expect(VisitFormValidation.isSlotDisabled('06:00', today, lateAfternoon), isFalse);
      expect(VisitFormValidation.isSlotDisabled('05:00', today, lateAfternoon), isTrue);
    });
  });

  group('describeSubmitError', () {
    test('a StateError\'s own message is shown verbatim', () {
      expect(
        describeSubmitError(StateError('Sign in to book a visit.'), "Couldn't book this visit"),
        'Sign in to book a visit.',
      );
    });

    test('any other error surfaces its own text with the given prefix', () {
      expect(
        describeSubmitError(Exception('network unreachable'), "Couldn't book this visit"),
        contains('network unreachable'),
      );
    });
  });
}
