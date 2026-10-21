// T5 builder-project tag parity guard.
//
// Scope is the TAG only: attaching a listing to an existing builder project.
// Creating projects and the inventory subsystem are out of scope by decision.
//
// The sharp edge here is that React DELETES the project keys when a listing is
// untagged (PropertyWizard.tsx:1603) rather than blanking them — which fights
// both Phase 0's merge (which only ever adds keys) and T1's typed-empty fill.
// Those interactions are asserted explicitly.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:propcid_app/models/tagged_project.dart';
import 'package:propcid_app/providers/post_property_provider.dart';
import 'package:propcid_app/screens/post_property/listing_field_keys.dart';

TaggedProject project({
  String id = 'proj-1',
  String title = 'Prestige Lakeside',
  String location = 'Whitefield, Bengaluru',
  String? builderName = 'Prestige Group',
  String? status = 'Under Construction',
}) =>
    TaggedProject(
      id: id,
      title: title,
      location: location,
      builderId: 'builder-1',
      builderName: builderName,
      status: status,
    );

/// Mirrors PropertyService._applyProjectTag.
Map<String, dynamic> applyProjectTag(
  Map<String, dynamic> meta,
  PostPropertyProvider p,
) {
  if (p.projectId.isNotEmpty) {
    meta['projectId'] = p.projectId;
    if (p.projectName.isNotEmpty) meta['projectName'] = p.projectName;
    if (p.builderName.isNotEmpty) meta['builderName'] = p.builderName;
    if (p.projectLocation.isNotEmpty) {
      meta['projectLocation'] = p.projectLocation;
    }
  } else {
    meta.remove('projectId');
    meta.remove('projectLocation');
    if (p.projectName.isNotEmpty) {
      meta['projectName'] = p.projectName;
    } else {
      meta.remove('projectName');
    }
    if (p.builderName.isNotEmpty) {
      meta['builderName'] = p.builderName;
    } else {
      meta.remove('builderName');
    }
  }
  return meta;
}

/// Mirrors PropertyService._fillTypedEmpties, including the T5 exception.
Map<String, dynamic> fillTypedEmpties(Map<String, dynamic> meta) {
  for (final key in kAllReactMetadataKeys) {
    if (kNestedObjectMetadataKeys.contains(key)) continue;
    if (kProjectTagMetadataKeys.contains(key)) continue;
    meta.putIfAbsent(key, () => '');
  }
  return meta;
}

void main() {
  late PostPropertyProvider p;

  setUp(() {
    WidgetsFlutterBinding.ensureInitialized();
    p = PostPropertyProvider();
  });

  group('Selecting a project', () {
    test('copies title, location, builder name and status onto the form', () {
      p.selectProject(project());

      expect(p.projectId, 'proj-1');
      expect(p.projectName, 'Prestige Lakeside');
      expect(p.projectLocation, 'Whitefield, Bengaluru');
      expect(p.builderName, 'Prestige Group');
      expect(p.text('propertyStatus'), 'Under Construction');
      expect(p.hasProjectTag, isTrue);
    });

    test('a project without a builder name does not wipe a typed one', () {
      p.setBuilderName('Typed By Hand');
      p.selectProject(project(builderName: null));
      expect(p.builderName, 'Typed By Hand');
    });

    test('a project without a status does not wipe a chosen one', () {
      p.setText('propertyStatus', 'Ready to Move');
      p.selectProject(project(status: null));
      expect(p.text('propertyStatus'), 'Ready to Move');
    });
  });

  group('Clearing a tag', () {
    test('clears id and location but KEEPS the builder name', () {
      // React's else-branch resets only projectId/projectLocation, so a broker
      // who typed a builder name keeps it after untagging.
      p.selectProject(project());
      p.selectProject(null);

      expect(p.projectId, isEmpty);
      expect(p.projectLocation, isEmpty);
      expect(p.builderName, 'Prestige Group');
      expect(p.hasProjectTag, isFalse);
    });
  });

  group('Metadata contract', () {
    test('tagged listing writes all four keys', () {
      p.selectProject(project());
      final meta = applyProjectTag(<String, dynamic>{}, p);

      expect(meta['projectId'], 'proj-1');
      expect(meta['projectName'], 'Prestige Lakeside');
      expect(meta['builderName'], 'Prestige Group');
      expect(meta['projectLocation'], 'Whitefield, Bengaluru');
    });

    test('untagging REMOVES the keys rather than blanking them', () {
      p.selectProject(project());
      final tagged = applyProjectTag(<String, dynamic>{}, p);
      expect(tagged.containsKey('projectId'), isTrue);

      p.selectProject(null);
      p.setBuilderName('');
      final cleared = applyProjectTag(tagged, p);

      expect(cleared.containsKey('projectId'), isFalse);
      expect(cleared.containsKey('projectLocation'), isFalse);
      expect(cleared.containsKey('builderName'), isFalse);

      // projectName is deliberately NOT cleared. React's onSelect(null) resets
      // only projectId and projectLocation (BasicInfoStep.tsx:686), and
      // projectName has no input anywhere in the wizard — so it survives the
      // untag and keeps being written. Matched rather than "fixed": diverging
      // here would make the app and the web disagree about a stored key.
      expect(cleared['projectName'], 'Prestige Lakeside');
    });

    test('an untagged listing keeps no projectId even with a lingering name',
        () {
      // The consequence of the quirk above: the name hangs around, but the id
      // is gone, so nothing links the listing to the project any more.
      p.selectProject(project());
      p.selectProject(null);
      final meta = applyProjectTag(<String, dynamic>{'projectId': 'proj-1'}, p);

      expect(meta.containsKey('projectId'), isFalse);
      expect(meta['projectName'], 'Prestige Lakeside');
      expect(p.hasProjectTag, isFalse);
    });

    test('a retained builder name survives untagging', () {
      p.selectProject(project());
      p.selectProject(null);
      final meta = applyProjectTag(<String, dynamic>{'projectId': 'proj-1'}, p);

      expect(meta.containsKey('projectId'), isFalse);
      expect(meta['builderName'], 'Prestige Group');
    });
  });

  group('Interaction with the Phase 0 merge', () {
    test('clearing a tag actually sticks through the merge', () {
      // The whole reason _applyProjectTag runs AFTER the merge: removing a key
      // from the freshly built map is undone by {...existing, ...fresh}.
      final existing = <String, dynamic>{
        'projectId': 'proj-1',
        'projectName': 'Prestige Lakeside',
        'projectLocation': 'Whitefield, Bengaluru',
      };
      p.selectProject(null);
      p.setBuilderName('');

      final merged = <String, dynamic>{...existing, ...<String, dynamic>{}};
      final result = applyProjectTag(merged, p);

      expect(result.containsKey('projectId'), isFalse);
      expect(result.containsKey('projectLocation'), isFalse);
    });

    test('the WRONG ordering would resurrect the tag', () {
      // Documents the hazard: strip first, then merge, and the stored blob
      // simply puts the tag back.
      final existing = <String, dynamic>{'projectId': 'proj-1'};
      p.selectProject(null);

      final stripped = applyProjectTag(<String, dynamic>{}, p);
      final wrong = <String, dynamic>{...existing, ...stripped};

      expect(wrong['projectId'], 'proj-1',
          reason: 'demonstrates why the tag is applied post-merge');
    });
  });

  group('Interaction with the T1 typed-empty fill', () {
    test('project keys are NOT filled with empty strings', () {
      p.selectProject(null);
      final meta = fillTypedEmpties(applyProjectTag(<String, dynamic>{}, p));

      for (final key in kProjectTagMetadataKeys) {
        expect(meta.containsKey(key), isFalse,
            reason: '$key must be absent, not blank, when untagged');
      }
    });

    test('other allow-list keys are still filled', () {
      p.selectProject(null);
      final meta = fillTypedEmpties(applyProjectTag(<String, dynamic>{}, p));
      expect(meta['brokerage'], '');
    });

    test('a real tag survives the fill', () {
      p.selectProject(project());
      final meta = fillTypedEmpties(applyProjectTag(<String, dynamic>{}, p));
      expect(meta['projectId'], 'proj-1');
    });
  });

  group('Edit hydration', () {
    test('reads project_id from the column, names from metadata', () {
      p.initFromRawData(
        editingPropertyId: 'prop-1',
        propertyRow: {
          'category': 'residential',
          'property_type': 'sell',
          'project_id': 'proj-9',
          'metadata': <String, dynamic>{
            'projectName': 'Stored Name',
            'projectLocation': 'Stored Location',
            'builderName': 'Stored Builder',
          },
        },
      );

      expect(p.projectId, 'proj-9');
      expect(p.projectName, 'Stored Name');
      expect(p.projectLocation, 'Stored Location');
      expect(p.builderName, 'Stored Builder');
    });

    test('falls back to metadata.projectId when the column is null', () {
      p.initFromRawData(
        editingPropertyId: 'prop-1',
        propertyRow: {
          'category': 'residential',
          'property_type': 'sell',
          'metadata': <String, dynamic>{'projectId': 'proj-meta'},
        },
      );
      expect(p.projectId, 'proj-meta');
    });

    test('an untagged listing hydrates with no tag', () {
      p.initFromRawData(
        editingPropertyId: 'prop-1',
        propertyRow: {
          'category': 'residential',
          'property_type': 'sell',
          'metadata': <String, dynamic>{},
        },
      );
      expect(p.hasProjectTag, isFalse);
      expect(p.projectId, isEmpty);
    });
  });

  group('project_id column', () {
    test('is null when untagged — the column is a uuid FK', () {
      String? columnValue(PostPropertyProvider p) =>
          p.projectId.isEmpty ? null : p.projectId;

      expect(columnValue(p), isNull);
      p.selectProject(project());
      expect(columnValue(p), 'proj-1');
      p.selectProject(null);
      expect(columnValue(p), isNull);
    });
  });

  group('Reset', () {
    test('clears the tag', () {
      p.selectProject(project());
      p.reset();

      expect(p.projectId, isEmpty);
      expect(p.projectName, isEmpty);
      expect(p.projectLocation, isEmpty);
      expect(p.builderName, isEmpty);
    });
  });
}
