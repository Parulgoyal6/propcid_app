// core/utils/public_media_url.dart
//
// Rewrites a Supabase Storage `getPublicUrl()` result onto the app's
// configured public-media host (`MEDIA_URL`), so newly uploaded public media
// is served from that host instead of the Supabase API domain. The upload
// itself is untouched — this only rewrites the URL string handed back after
// `uploadBinary`/`getPublicUrl` already succeeded against the real Supabase
// client/API.
//
// Only a Storage *public object* URL is rewritten:
// `.../storage/v1/object/public/<bucket>/<path>`. A signed URL
// (`.../object/sign/...`), any other private-download shape, or a URL that
// isn't Supabase Storage at all is returned untouched — this must never
// touch chat attachments, collaboration files or verification documents'
// signed-URL flows, none of which call `getPublicUrl` in the first place.
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PublicMediaUrl {
  PublicMediaUrl._();

  static const String _publicObjectPrefix = '/storage/v1/object/public/';

  /// Rewrites [publicUrl] onto the configured `MEDIA_URL` host.
  ///
  /// Returns [publicUrl] unchanged when:
  ///   * `MEDIA_URL` isn't set in the active `.env` — e.g. a production
  ///     configuration, which deliberately never carries this key, keeps
  ///     serving files from the original Supabase host exactly as it does
  ///     today;
  ///   * [publicUrl] isn't a Supabase Storage *public* object URL.
  ///
  /// Throws a [StateError] when `MEDIA_URL` **is** configured but isn't a
  /// usable absolute http(s) URL, rather than silently handing back a
  /// broken media URL from a upload call that otherwise reports success.
  static String resolve(String publicUrl) {
    final configured = dotenv.env['MEDIA_URL']?.trim();
    if (configured == null || configured.isEmpty) return publicUrl;

    final mediaHost = Uri.tryParse(configured);
    final isUsable =
        mediaHost != null &&
        mediaHost.isAbsolute &&
        (mediaHost.scheme == 'http' || mediaHost.scheme == 'https') &&
        mediaHost.host.isNotEmpty;
    if (!isUsable) {
      throw StateError(
        'MEDIA_URL is configured but is not a usable http(s) URL: '
        '"$configured"',
      );
    }

    final source = Uri.tryParse(publicUrl);
    if (source == null || !source.path.startsWith(_publicObjectPrefix)) {
      return publicUrl;
    }

    // Only the scheme/host/port change — path, encoded characters and query
    // string are carried over exactly as Supabase produced them.
    return source
        .replace(
          scheme: mediaHost.scheme,
          host: mediaHost.host,
          port: mediaHost.hasPort ? mediaHost.port : null,
        )
        .toString();
  }
}
