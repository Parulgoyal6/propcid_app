import 'package:propcid_app/services/property_inquiry_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakePropertyInquiryService extends PropertyInquiryService {
  FakePropertyInquiryService()
      : super(
          client: SupabaseClient(
            'http://localhost:54321',
            'test-anon-key',
            // Without this, GoTrue starts a real periodic auto-refresh
            // timer that outlives the widget tree and fails flutter_test's
            // "no pending timers after dispose" check.
            authOptions: const AuthClientOptions(autoRefreshToken: false),
          ),
        );

  Object? nextError;
  final List<Map<String, dynamic>> submitCalls = <Map<String, dynamic>>[];

  @override
  Future<void> submit({
    required String propertyId,
    required String message,
    String? contactPhone,
    String? contactEmail,
    String? preferredContactTime,
  }) async {
    submitCalls.add({
      'propertyId': propertyId,
      'message': message,
      'contactPhone': contactPhone,
      'contactEmail': contactEmail,
      'preferredContactTime': preferredContactTime,
    });
    final error = nextError;
    if (error != null) {
      nextError = null;
      throw error;
    }
  }
}
