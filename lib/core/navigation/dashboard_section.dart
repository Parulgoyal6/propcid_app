// core/navigation/dashboard_section.dart
//
// The `ManageDashboardDispatcher` route's `arguments['section']` key —
// which tab (Leads or Visits) a role dashboard should open on, independent
// of which of the four role screens the dispatcher ends up building.
//
// Every role dashboard already names its own Leads/Visits tab enum members
// `leads`/`visits` (`BuilderSection.leads`, `BrokerSection.visits`, …), so a
// plain string matching those member names lets each dashboard resolve its
// own initial tab with a safe `Enum.values.byName`-style lookup, without a
// shared enum type the four separate per-role enums would all have to
// implement or convert to/from.
class DashboardSection {
  DashboardSection._();

  static const String leads = 'leads';
  static const String visits = 'visits';

  /// `BuilderSection.team` — the only role dashboard with a Team tab. Passed
  /// by a tapped `team_activity` notification whose `data.route` is
  /// `/manage-builder-dashboard`; harmless on every other role dashboard,
  /// which doesn't recognise it and falls back to its own default tab.
  static const String team = 'team';
}
