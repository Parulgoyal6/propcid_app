// Pins the exact initial-section resolution expression every one of the
// four role dashboards now uses to seed its tab state from
// `ManageDashboardDispatcher.initialSection` —
//
//   TheRoleSection.values.firstWhere(
//     (s) => s.name == initialSection,
//     orElse: () => TheRoleSection.<existing default>,
//   )
//
// — against each role's own real section enum, rather than a stand-in. A
// full widget-level test of each dashboard's initial tab would need heavy
// Provider/service mocking per role (out of this fix's narrow scope); this
// instead pins the resolution CONTRACT itself: a valid `'leads'`/`'visits'`
// value lands on that section, and anything else — including `null`, which
// is what every existing caller of `ManageDashboardScreen`'s route already
// passes — falls back to the dashboard's unchanged default, never throws.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/core/navigation/dashboard_section.dart';
import 'package:propcid_app/screens/dashboard/broker_dashboard_screen.dart'
    show BrokerSection;
import 'package:propcid_app/screens/dashboard/builder_dashboard_screen.dart'
    show BuilderSection;
import 'package:propcid_app/screens/dashboard/individual_dashboard_screen.dart'
    show IndividualSection;
import 'package:propcid_app/screens/dashboard/influencer_dashboard_screen.dart'
    show InfluencerSection;

T _resolve<T extends Enum>(List<T> values, String? initialSection, T fallback) {
  return values.firstWhere(
    (s) => s.name == initialSection,
    orElse: () => fallback,
  );
}

void main() {
  group('Builder (default: overview)', () {
    test('null keeps the existing default', () {
      expect(
        _resolve(BuilderSection.values, null, BuilderSection.overview),
        BuilderSection.overview,
      );
    });
    test(DashboardSection.leads, () {
      expect(
        _resolve(
          BuilderSection.values,
          DashboardSection.leads,
          BuilderSection.overview,
        ),
        BuilderSection.leads,
      );
    });
    test(DashboardSection.visits, () {
      expect(
        _resolve(
          BuilderSection.values,
          DashboardSection.visits,
          BuilderSection.overview,
        ),
        BuilderSection.visits,
      );
    });
    test('an unrecognised value falls back safely, never throws', () {
      expect(
        _resolve(
          BuilderSection.values,
          'not-a-real-section',
          BuilderSection.overview,
        ),
        BuilderSection.overview,
      );
    });
  });

  group('Broker (default: analytics)', () {
    test('null keeps the existing default', () {
      expect(
        _resolve(BrokerSection.values, null, BrokerSection.analytics),
        BrokerSection.analytics,
      );
    });
    test(DashboardSection.leads, () {
      expect(
        _resolve(
          BrokerSection.values,
          DashboardSection.leads,
          BrokerSection.analytics,
        ),
        BrokerSection.leads,
      );
    });
    test(DashboardSection.visits, () {
      expect(
        _resolve(
          BrokerSection.values,
          DashboardSection.visits,
          BrokerSection.analytics,
        ),
        BrokerSection.visits,
      );
    });
  });

  group('Individual (default: analytics)', () {
    test('null keeps the existing default', () {
      expect(
        _resolve(IndividualSection.values, null, IndividualSection.analytics),
        IndividualSection.analytics,
      );
    });
    test(DashboardSection.leads, () {
      expect(
        _resolve(
          IndividualSection.values,
          DashboardSection.leads,
          IndividualSection.analytics,
        ),
        IndividualSection.leads,
      );
    });
    test(DashboardSection.visits, () {
      expect(
        _resolve(
          IndividualSection.values,
          DashboardSection.visits,
          IndividualSection.analytics,
        ),
        IndividualSection.visits,
      );
    });
  });

  group('Influencer (default: analytics)', () {
    test('null keeps the existing default', () {
      expect(
        _resolve(InfluencerSection.values, null, InfluencerSection.analytics),
        InfluencerSection.analytics,
      );
    });
    test(DashboardSection.leads, () {
      expect(
        _resolve(
          InfluencerSection.values,
          DashboardSection.leads,
          InfluencerSection.analytics,
        ),
        InfluencerSection.leads,
      );
    });
    test(DashboardSection.visits, () {
      expect(
        _resolve(
          InfluencerSection.values,
          DashboardSection.visits,
          InfluencerSection.analytics,
        ),
        InfluencerSection.visits,
      );
    });
  });
}
