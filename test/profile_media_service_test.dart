// Phase 4 — profile media upload.
//
// `ProfileMediaService` is deliberately self-contained: it does not import
// `PropertyService`, which is treated as stable. The cost of that is a second
// copy of the path/MIME conventions, so this file pins them.
//
// THE POINT OF THE MIME AND PATH ASSERTIONS
// -----------------------------------------
// A wrong bucket or a path that does not begin with the user id fails the storage
// policy with an opaque error — the policies require `(storage.foldername(name))[1]
// = auth.uid()`. A missing content type is worse than an error: Supabase stores
// `application/octet-stream`, the upload succeeds, and the image then downloads
// instead of rendering wherever the portal shows it. Neither is visible without a
// live bucket, so the shapes are asserted here instead.
import 'package:flutter_test/flutter_test.dart';

import 'package:propcid_app/services/profile_media_service.dart';

void main() {
  const userId = 'a1b2c3d4-0000-0000-0000-000000000000';
  const timestamp = 1770000000000;

  group('buckets follow the portal, including its inconsistency', () {
    test('avatars and documents go to the avatars bucket', () {
      // EditProfile.tsx:237 and AvatarUploadModal.tsx:164.
      expect(ProfileMediaService.avatarBucket, 'avatars');
    });

    test('covers go to property-media, as the portal genuinely does', () {
      // BackgroundUploadModal.tsx:161. Not a typo on our side: a cover uploaded
      // by the app must be readable at the URL the portal expects.
      expect(ProfileMediaService.coverBucket, 'property-media');
    });
  });

  group('every path starts with the user id', () {
    // The storage policies match on the first folder segment. A path that does
    // not begin with the caller's uid is rejected.
    test('avatar', () {
      final path = ProfileMediaService.avatarPath(userId, 'jpg', timestamp);
      expect(path.split('/').first, userId);
      expect(path, '$userId/$timestamp.jpg');
    });

    test('cover', () {
      final path = ProfileMediaService.coverPath(userId, 'png', timestamp);
      expect(path.split('/').first, userId);
      expect(path, '$userId/${timestamp}_background.png');
    });

    test('document', () {
      for (final kind in ProfileDocumentKind.values) {
        final path = ProfileMediaService.documentPath(
          userId,
          kind,
          'jpg',
          timestamp,
        );
        expect(path.split('/').first, userId, reason: kind.name);
        expect(path, '$userId/${kind.slug}_$timestamp.jpg', reason: kind.name);
      }
    });

    test('no path contains a double slash or a trailing dot', () {
      final paths = <String>[
        ProfileMediaService.avatarPath(userId, 'jpg', timestamp),
        ProfileMediaService.coverPath(userId, 'jpg', timestamp),
        for (final k in ProfileDocumentKind.values)
          ProfileMediaService.documentPath(userId, k, 'jpg', timestamp),
      ];
      for (final p in paths) {
        expect(p.contains('//'), isFalse, reason: p);
        expect(p.endsWith('.'), isFalse, reason: p);
      }
    });
  });

  group('document slugs match the portal upload types', () {
    test('each kind carries the portal\'s prefix', () {
      // EditProfile.tsx:245 — "rera" | "gst" | "pan" | "proof" | "logo" | "aadhaar".
      expect(ProfileDocumentKind.rera.slug, 'rera');
      expect(ProfileDocumentKind.gst.slug, 'gst');
      expect(ProfileDocumentKind.pan.slug, 'pan');
      expect(ProfileDocumentKind.registrationProof.slug, 'proof');
      expect(ProfileDocumentKind.aadhaar.slug, 'aadhaar');
      expect(ProfileDocumentKind.companyLogo.slug, 'logo');
    });

    test('slugs are unique, so two kinds cannot collide on one path', () {
      final slugs = ProfileDocumentKind.values.map((k) => k.slug).toList();
      expect(slugs.toSet().length, slugs.length);
    });

    test('only the company logo targets a column', () {
      final columnTargets = ProfileDocumentKind.values
          .where((k) => !k.target.startsWith('social_media.'))
          .toList();
      expect(columnTargets, [ProfileDocumentKind.companyLogo]);
      expect(ProfileDocumentKind.companyLogo.target, 'company_logo_url');
    });
  });

  group('extension parsing', () {
    test('lowercases and takes the last segment', () {
      expect(ProfileMediaService.extensionOf('photo.JPG'), 'jpg');
      expect(ProfileMediaService.extensionOf('a.b.png'), 'png');
    });

    test('defaults to jpg when there is no usable extension', () {
      // image_picker can hand back a cache filename with no extension; without a
      // default the path would end in "." and the MIME lookup would miss.
      expect(ProfileMediaService.extensionOf('noextension'), 'jpg');
      expect(ProfileMediaService.extensionOf('trailingdot.'), 'jpg');
      expect(ProfileMediaService.extensionOf(''), 'jpg');
    });
  });

  group('MIME mapping', () {
    test('covers every format image_picker can return', () {
      expect(ProfileMediaService.mimeFromExtension('jpg'), 'image/jpeg');
      expect(ProfileMediaService.mimeFromExtension('jpeg'), 'image/jpeg');
      expect(ProfileMediaService.mimeFromExtension('png'), 'image/png');
      expect(ProfileMediaService.mimeFromExtension('webp'), 'image/webp');
      expect(ProfileMediaService.mimeFromExtension('heic'), 'image/heic');
      expect(ProfileMediaService.mimeFromExtension('heif'), 'image/heif');
      expect(ProfileMediaService.mimeFromExtension('gif'), 'image/gif');
    });

    test('is case-insensitive', () {
      expect(ProfileMediaService.mimeFromExtension('PNG'), 'image/png');
    });

    test('agrees with the property feature on the shared formats', () {
      // PropertyService._mimeFromExt is private and unreachable, so the mapping is
      // duplicated by necessity. These four are the formats both accept, and this
      // is what catches a drift between the two copies.
      const shared = {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'webp': 'image/webp',
        'heic': 'image/heic',
      };
      shared.forEach((ext, mime) {
        expect(ProfileMediaService.mimeFromExtension(ext), mime, reason: ext);
      });
    });

    test(
      'an unknown extension falls back to octet-stream, as property does',
      () {
        expect(
          ProfileMediaService.mimeFromExtension('xyz'),
          'application/octet-stream',
        );
      },
    );

    test('video types are NOT mapped — only images can be picked', () {
      // PropertyService maps mp4/mov because a listing accepts video. A profile
      // photo cannot be one, so mapping them here would imply support that the
      // picker does not offer.
      expect(
        ProfileMediaService.mimeFromExtension('mp4'),
        'application/octet-stream',
      );
      expect(
        ProfileMediaService.mimeFromExtension('mov'),
        'application/octet-stream',
      );
    });
  });

  group('Aadhaar/PAN — the only kinds that accept PDF', () {
    test('acceptsPdf is true only for aadhaar (front/back) and pan', () {
      for (final kind in ProfileDocumentKind.values) {
        final expected =
            kind == ProfileDocumentKind.aadhaar ||
            kind == ProfileDocumentKind.aadhaarBack ||
            kind == ProfileDocumentKind.pan;
        expect(
          ProfileMediaService.acceptsPdf(kind),
          expected,
          reason: kind.name,
        );
      }
    });

    test('go to the private documents bucket, not avatars', () {
      expect(ProfileMediaService.verificationDocumentBucket, 'documents');
      expect(
        ProfileMediaService.verificationDocumentBucket,
        isNot(ProfileMediaService.avatarBucket),
      );
    });

    // Regression test for the incident this closes: Builder/Broker/
    // Influencer registration never passed `private: true` for Aadhaar/PAN,
    // so those uploads landed in the public `avatars` bucket. `uploadDocument`
    // now ignores a `false` caller request for these kinds specifically —
    // this pins that down independent of any one caller remembering to ask
    // for it correctly.
    test(
      'uploadDocument always routes Aadhaar/PAN private, regardless of what the caller asked for',
      () {
        for (final kind in [
          ProfileDocumentKind.aadhaar,
          ProfileDocumentKind.aadhaarBack,
          ProfileDocumentKind.pan,
        ]) {
          expect(
            ProfileMediaService.resolvesPrivate(
              callerRequestedPrivate: false,
              kind: kind,
            ),
            isTrue,
            reason:
                '${kind.name}: a caller forgetting `private: true` (like every '
                'registration screen did) must not leak it to the public bucket',
          );
          expect(
            ProfileMediaService.resolvesPrivate(
              callerRequestedPrivate: true,
              kind: kind,
            ),
            isTrue,
            reason: '${kind.name}: an explicit true must still go private',
          );
        }
      },
    );

    test(
      'uploadDocument leaves RERA/GST/proof/logo exactly as the caller asked — this fix is scoped to Aadhaar/PAN only',
      () {
        for (final kind in [
          ProfileDocumentKind.rera,
          ProfileDocumentKind.gst,
          ProfileDocumentKind.registrationProof,
          ProfileDocumentKind.companyLogo,
        ]) {
          expect(
            ProfileMediaService.resolvesPrivate(
              callerRequestedPrivate: false,
              kind: kind,
            ),
            isFalse,
            reason: '${kind.name}: unaffected by this fix, stays public',
          );
          expect(
            ProfileMediaService.resolvesPrivate(
              callerRequestedPrivate: true,
              kind: kind,
            ),
            isTrue,
            reason:
                "${kind.name}: a caller that DOES explicitly ask for private "
                'is still honoured — this only ever widens privacy',
          );
        }
      },
    );

    test('path mirrors the portal\'s imageUploader.ts exactly', () {
      const uuid = '11111111-2222-3333-4444-555555555555';
      final path = ProfileMediaService.verificationDocumentPath(
        userId,
        'pdf',
        uuid,
      );
      expect(path, '$userId/profiles/$userId/$uuid-original.pdf');
      expect(path.split('/').first, userId);
    });

    test('pdf maps to application/pdf', () {
      expect(ProfileMediaService.mimeFromExtension('pdf'), 'application/pdf');
      expect(ProfileMediaService.mimeFromExtension('PDF'), 'application/pdf');
    });

    test('the offered extensions are exactly image formats plus pdf', () {
      expect(ProfileMediaService.verificationDocumentExtensions, [
        'jpg',
        'jpeg',
        'png',
        'webp',
        'pdf',
      ]);
    });
  });

  group('validatePickedDocument — pure, no plugin or network needed', () {
    test('accepts a well-formed pdf under the size cap', () {
      expect(
        ProfileMediaService.validatePickedDocument(
          fileName: 'aadhaar.pdf',
          sizeBytes: 1024,
          bytesAvailable: true,
        ),
        isNull,
      );
    });

    test('accepts a well-formed image under the size cap', () {
      expect(
        ProfileMediaService.validatePickedDocument(
          fileName: 'pan.jpg',
          sizeBytes: 1024,
          bytesAvailable: true,
        ),
        isNull,
      );
    });

    test('rejects a disallowed extension', () {
      expect(
        ProfileMediaService.validatePickedDocument(
          fileName: 'aadhaar.docx',
          sizeBytes: 1024,
          bytesAvailable: true,
        ),
        isNotNull,
      );
    });

    test('rejects a file over 20MB', () {
      expect(
        ProfileMediaService.validatePickedDocument(
          fileName: 'aadhaar.pdf',
          sizeBytes: ProfileMediaService.verificationDocumentMaxBytes + 1,
          bytesAvailable: true,
        ),
        isNotNull,
      );
    });

    test('accepts exactly the 20MB boundary', () {
      expect(
        ProfileMediaService.validatePickedDocument(
          fileName: 'aadhaar.pdf',
          sizeBytes: ProfileMediaService.verificationDocumentMaxBytes,
          bytesAvailable: true,
        ),
        isNull,
      );
    });

    test('rejects when the platform could not hand back bytes', () {
      // Happens on Android when file_picker is called without withData —
      // asserted here so that flag can never silently regress.
      expect(
        ProfileMediaService.validatePickedDocument(
          fileName: 'aadhaar.pdf',
          sizeBytes: 1024,
          bytesAvailable: false,
        ),
        isNotNull,
      );
    });
  });

  group('ProfileMediaValidationError', () {
    test('toString is the bare message, not "Exception: ..."', () {
      final error = ProfileMediaValidationError('That file is over 20MB.');
      expect(error.toString(), 'That file is over 20MB.');
    });
  });

  group('compression ceilings match the portal', () {
    test('avatar 1024, cover 1920', () {
      // AvatarUploadModal.tsx:155 and BackgroundUploadModal.tsx:152.
      expect(ProfileMediaService.avatarMaxDimension, 1024);
      expect(ProfileMediaService.coverMaxDimension, 1920);
    });

    test('documents allow more detail than an avatar', () {
      // A photographed certificate must stay legible.
      expect(
        ProfileMediaService.documentMaxDimension,
        greaterThan(ProfileMediaService.avatarMaxDimension),
      );
    });

    test('quality is a sane JPEG value', () {
      expect(ProfileMediaService.jpegQuality, inInclusiveRange(70, 95));
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// NOT COVERED HERE
//
// The upload itself, and the `profiles` write that follows it, need a live bucket
// and a signed-in session — neither is available in this environment. What is
// asserted above is every value that would make such an upload fail or silently
// misbehave. End-to-end verification belongs with the Android device validation
// tracked as a release requirement (V1).
