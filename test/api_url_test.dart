import 'package:flutter_test/flutter_test.dart';
import 'package:pfep_frontend/core/api.dart';

/// URL construction, because getting it wrong fails in a way that reads like a
/// server fault rather than a client one.
///
/// Two real incidents are pinned down here:
///
///  1. The client held a *host* and appended `/api` itself. Mounted inside the
///     CRM the API root is `/api/v1/pfep`, so appending produced
///     `/api/v1/pfep/api/auth/login`; and the web build defaulted to the
///     frontend's own Worker origin, where a POST to a static-asset host
///     answers 405 Method Not Allowed. Neither reads as a base-URL mistake
///     from the browser's network tab.
///
///  2. A build shipped with `https://host//api/v1/pfep` after a find-and-
///     replace caught the slash. It happened to work, which is worse than
///     failing: the same string is also handed to image URLs and written into
///     exported workbooks.
const _root = 'https://uat-api.vistarlogitek.com/api/v1/pfep';

void main() {
  group('API root is used exactly as configured', () {
    test('a mounted root is not given an extra /api', () {
      final c = ApiClient(baseUrl: _root);
      expect(c.baseUrl, _root);
      // The old behaviour appended '/api'; this is what must not come back.
      expect(c.baseUrl.endsWith('/api'), isFalse);
    });

    test('a standalone root keeps its own /api', () {
      final c = ApiClient(baseUrl: 'http://localhost:4000/api');
      expect(c.baseUrl, 'http://localhost:4000/api');
    });
  });

  group('a hand-written root is normalised', () {
    test('a doubled slash in the path is collapsed', () {
      expect(
        normalizeApiRoot('https://uat-api.vistarlogitek.com//api/v1/pfep'),
        _root,
      );
    });

    test('the scheme is left alone', () {
      expect(normalizeApiRoot('https://h/api'), 'https://h/api');
      expect(normalizeApiRoot('http://h:4000/api'), 'http://h:4000/api');
    });

    test('a trailing slash is trimmed', () {
      // Left on, every path would be built with a double slash.
      expect(normalizeApiRoot('https://h/api/v1/pfep/'), 'https://h/api/v1/pfep');
      expect(normalizeApiRoot('https://h/api/v1/pfep///'), 'https://h/api/v1/pfep');
    });

    test('surrounding whitespace does not survive', () {
      expect(normalizeApiRoot('  https://h/api  '), 'https://h/api');
    });

    test('the client normalises what it is handed', () {
      expect(ApiClient(baseUrl: 'https://h//api/v1/pfep/').baseUrl, 'https://h/api/v1/pfep');
    });
  });

  group('fileUrl resolves against the origin, not the API root', () {
    test('a mounted photo path is not prefixed twice', () {
      final c = ApiClient(baseUrl: _root);
      // The server emits this absolute from the site root, mount included.
      const path = '/api/v1/pfep/photos/pho_1/file?exp=123&sig=abc';
      expect(
        c.fileUrl(path),
        'https://uat-api.vistarlogitek.com/api/v1/pfep/photos/pho_1/file?exp=123&sig=abc',
      );
    });

    test('a standalone photo path still resolves', () {
      final c = ApiClient(baseUrl: 'http://localhost:4000/api');
      expect(c.fileUrl('/api/photos/pho_1/file'), 'http://localhost:4000/api/photos/pho_1/file');
    });

    test('a non-default port survives', () {
      final c = ApiClient(baseUrl: 'http://192.168.1.20:4000/api');
      expect(c.fileUrl('/api/photos/x/file'), 'http://192.168.1.20:4000/api/photos/x/file');
    });

    test('an already-absolute URL is passed through', () {
      final c = ApiClient(baseUrl: _root);
      expect(c.fileUrl('https://cdn.example.com/x.jpg'), 'https://cdn.example.com/x.jpg');
    });
  });

  group('the default root a build falls back to', () {
    // Regression: mobile defaulted to http://10.0.2.2:4000/api, the emulator's
    // alias for the development machine's loopback. On a real handset nothing
    // answers there, so an APK built without --dart-define failed every call
    // and reported no connection on a phone that was online.
    test('mobile points at a backend that exists, not the emulator loopback', () {
      final root = defaultApiRoot(isMobile: true);
      expect(root, kDeployedApiRoot);
      expect(root, startsWith('https://'));
      expect(root, isNot(contains('10.0.2.2')));
      expect(root, isNot(contains('localhost')));
      expect(root, isNot(contains('127.0.0.1')));
    });

    test('the mobile default survives normalisation unchanged', () {
      // It is handed straight to Dio as a baseUrl, so a stray or doubled slash
      // in the constant would reach photo URLs and exported workbooks too.
      expect(normalizeApiRoot(kDeployedApiRoot), kDeployedApiRoot);
      expect(ApiClient(baseUrl: kDeployedApiRoot).baseUrl, kDeployedApiRoot);
    });

    test('web and desktop stay local, so _looksUnconfigured can spot them', () {
      // The deployed web build is always built with --dart-define; the point of
      // the local default is that a build which was not is recognisable.
      expect(defaultApiRoot(isMobile: false), 'http://localhost:4000/api');
    });
  });
}
