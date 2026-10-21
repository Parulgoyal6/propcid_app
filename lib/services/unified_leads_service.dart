// services/unified_leads_service.dart
//
// Merges `property_inquiries` and `property_visit_bookings` into one list —
// the mobile port of `IncomingLeadsManager.tsx`'s "every incoming lead"
// dashboard, scoped to the two sources this app actually creates from the
// buyer side today (not `project_visit_bookings`/`profile_visit_requests`).
//
// Deliberately composes the existing, already-tested `BrokerLeadService` and
// `PropertyVisitBookingService` rather than re-querying either table itself
// — same reasoning `broker_sections_service.dart` gives for reusing
// `PropertyService.getPropertiesByUser`: don't re-run a query something else
// already runs correctly.
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/broker_section_options.dart';
import '../models/broker_section_models.dart';
import '../models/property_model.dart';
import 'broker_sections_service.dart';

class UnifiedLeadsService {
  UnifiedLeadsService({
    BrokerLeadService? leadService,
    PropertyVisitBookingService? visitService,
    SupabaseClient? client,
  }) : _leadService = leadService ?? BrokerLeadService(client: client),
       _visitService =
           visitService ?? PropertyVisitBookingService(client: client);

  final BrokerLeadService _leadService;
  final PropertyVisitBookingService _visitService;

  /// Every inquiry and visit booking across [properties], newest first —
  /// `IncomingLeadsManager.tsx:157-270`'s merge-and-sort, minus the two
  /// sources this app doesn't create yet.
  Future<List<UnifiedLead>> listForProperties(
    List<PropertyModel> properties,
  ) async {
    final results = await Future.wait([
      _leadService.listForProperties(properties),
      _visitService.listForProperties(properties),
    ]);
    final inquiries = results[0] as List<BrokerLead>;
    final visits = results[1] as List<PropertyVisitBooking>;

    final merged = <UnifiedLead>[
      ...inquiries.map(UnifiedLead.fromInquiry),
      ...visits.map(UnifiedLead.fromVisit),
    ];
    final deduped = _mergeSamePersonLeads(merged);
    deduped.sort((a, b) {
      final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });
    return deduped;
  }

  /// Combines an inquiry-sourced and a visit-sourced lead from the same
  /// person on the same property into a single card, so Call, Email and the
  /// status Update all live on one entry instead of being split across two.
  /// The portal's own `incoming-leads-inbox` function never does this merge
  /// (it just concatenates every source) — this is a Flutter-only UX
  /// improvement, not a parity fix, scoped to what the user asked for.
  ///
  /// Deliberately narrow: it only folds together *one inquiry and one visit*
  /// per person+property (the actual duplicate being reported). Two genuine
  /// inquiries, or two genuine visit requests, from the same person stay as
  /// separate cards — each still carries its own independent status, so
  /// collapsing those would silently drop one.
  ///
  /// Only leads carrying a [UnifiedLead.requesterUserId] can be matched this
  /// way, since that's the only reliable cross-source identity key
  /// available. Whichever of the pair is newer is kept as primary (its
  /// `id`/`source`/`status` decide where a later [setStatus] writes back);
  /// the other only backfills contact fields the primary is missing.
  List<UnifiedLead> _mergeSamePersonLeads(List<UnifiedLead> leads) {
    final byKey = <String, List<UnifiedLead>>{};
    final unmatched = <UnifiedLead>[];
    for (final lead in leads) {
      final userId = lead.requesterUserId;
      if (userId == null || userId.isEmpty) {
        unmatched.add(lead);
        continue;
      }
      final key = '$userId|${lead.propertyId}';
      byKey.putIfAbsent(key, () => []).add(lead);
    }

    final result = <UnifiedLead>[...unmatched];
    for (final group in byKey.values) {
      final inquiries = group
          .where((l) => l.source == UnifiedLeadSource.inquiry)
          .toList()
        ..sort(_byCreatedAtDesc);
      final visits = group
          .where((l) => l.source == UnifiedLeadSource.visit)
          .toList()
        ..sort(_byCreatedAtDesc);

      if (inquiries.isEmpty || visits.isEmpty) {
        result.addAll(group);
        continue;
      }

      final inquiry = inquiries.first;
      final visit = visits.first;
      final inquiryTime = inquiry.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final visitTime = visit.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      result.add(
        visitTime.compareTo(inquiryTime) >= 0
            ? visit.mergedWithContactFrom(inquiry)
            : inquiry.mergedWithContactFrom(visit),
      );
      result
        ..addAll(inquiries.skip(1))
        ..addAll(visits.skip(1));
    }
    return result;
  }

  static int _byCreatedAtDesc(UnifiedLead a, UnifiedLead b) {
    final aTime = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bTime.compareTo(aTime);
  }

  /// The same four counters [BrokerLeadService.statsFor] computes, but over
  /// the unified list — `IncomingLeadsManager.tsx:274-289`. `closedValue`
  /// still only counts closed *inquiry*-sourced leads (`:283`: `l.source ===
  /// "inquiry"`), since only `property_inquiries` leads carry a property
  /// sale/rent price worth totalling as "deal value".
  Future<BrokerLeadStats> statsFor(List<UnifiedLead> leads) async {
    if (leads.isEmpty) return BrokerLeadStats.empty;

    final total = leads.length;
    final newLeads = leads.where((l) => l.status == 'new').length;
    final active = leads
        .where((l) => kActiveBrokerLeadStatuses.contains(l.status))
        .length;
    final closed = leads.where((l) => l.status == 'closed').length;

    final closedInquiryPropertyIds = leads
        .where(
          (l) => l.source == UnifiedLeadSource.inquiry && l.status == 'closed',
        )
        .map((l) => l.propertyId)
        .toSet()
        .toList();
    final closedValue = await _closedInquiryValue(closedInquiryPropertyIds);

    return BrokerLeadStats(
      total: total,
      newLeads: newLeads,
      active: active,
      closed: closed,
      conversionRate: (closed / total) * 100,
      closedValue: closedValue,
    );
  }

  /// Sum of `properties.price` (portal's lossy parse) for [propertyIds] —
  /// the same read+fold `BrokerLeadService._fetchPrices`/`parsePortalPrice`
  /// does, kept as its own small query here rather than exposing that
  /// private method: it operates on a different filtered set (closed +
  /// inquiry-sourced ids pulled out of the unified list) than
  /// `BrokerLeadService.statsFor`'s own `List<BrokerLead>` input.
  Future<double> _closedInquiryValue(List<String> propertyIds) async {
    if (propertyIds.isEmpty) return 0;
    try {
      final rows = await _leadService.fetchRawPrices(propertyIds);
      return rows.values.fold<double>(0, (sum, price) => sum + price);
    } catch (e) {
      debugPrint('UnifiedLeadsService._closedInquiryValue failed: $e');
      return 0;
    }
  }

  /// Writes [lead]'s new unified [status] back to its own source table —
  /// `IncomingLeadsManager.tsx:298-334`'s `handleStatusChange`, split by
  /// [UnifiedLeadSource] the same way the portal branches on `lead.source`.
  Future<UnifiedLead> setStatus(UnifiedLead lead, String status) async {
    if (lead.source == UnifiedLeadSource.inquiry) {
      await _leadService.setStatus(leadId: lead.id, status: status);
    } else {
      await _visitService.updateStatusOnly(
        bookingId: lead.id,
        userId: lead.requesterUserId,
        propertyTitle: lead.propertyTitle ?? 'your property',
        status: visitLeadStatusToDb(status),
        propertyId: lead.propertyId,
      );
    }
    return lead.withStatus(status);
  }
}
