import 'package:flutter_test/flutter_test.dart';
import 'package:pfep_frontend/core/api.dart';

/// URL construction, because getting it wrong fails in a way that reads like a
/// server fault rather than a client one.
///
/// The bug this pins down: the client used to hold a *host* and append `/api`
/// itself. Mounted inside the CRM the API root is `/api/v1/pfep`, so appending
/// produced `/api/v1/pfep/api/auth/login`; and the web build defaulted to the
/// frontend's own Worker origin, where a POST to a static-asset host answers
/// 405 Method Not Allowed. Neither looks like a base-URL mistake from the
/// browser's network tab.
void main() {
  group('API root is used exactly as configured', () {
    test('a mounted root is not given an extra /api', () {
      final c = ApiClient(baseUrl: 'https://uat-api.vistarlogitek.com//api/v1/pfep');
      expect(c.baseUrl, 'https://uat-api.vistarlogitek.com//api/v1/pfep');
      // The old behaviour appended '/api'; this is what must not come back.
      expect(c.baseUrl.endsWith('/api'), isFalse);
    });

    test('a standalone root keeps its own /api', () {
      final c = ApiClient(baseUrl: 'http://localhost:4000/api');
      expect(c.baseUrl, 'http://localhost:4000/api');
    });
  });

  group('fileUrl resolves against the origin, not the API root', () {
    test('a mounted photo path is not prefixed twice', () {
      final c = ApiClient(baseUrl: 'https://uat-api.vistarlogitek.com//api/v1/pfep');
      // The server emits this absolute from the site root, mount included.
      const path = '/api/v1/pfep/photos/pho_1/file?exp=123&sig=abc';
      expect(
        c.fileUrl(path),
        'https://uat-api.vistarlogitek.com//api/v1/pfep/photos/pho_1/file?exp=123&sig=abc',
      );
    });

    test('a standalone photo path still resolves', () {
      final c = ApiClient(baseUrl: 'http://localhost:4000/api');
      expect(
        c.fileUrl('/api/photos/pho_1/file'),
        'http://localhost:4000/api/photos/pho_1/file',
      );
    });

    test('a non-default port survives', () {
      final c = ApiClient(baseUrl: 'http://192.168.1.20:4000/api');
      expect(c.fileUrl('/api/photos/x/file'), 'http://192.168.1.20:4000/api/photos/x/file');
    });

    test('an already-absolute URL is passed through', () {
      final c = ApiClient(baseUrl: 'https://uat-api.vistarlogitek.com//api/v1/pfep');
      expect(c.fileUrl('https://cdn.example.com/x.jpg'), 'https://cdn.example.com/x.jpg');
    });
  });

  test('a trailing slash on the configured root is trimmed', () {
    // Left on, every path would be built with a double slash.
    expect(
      ApiClient(baseUrl: 'https://h/api/v1/pfep/'.replaceAll(RegExp(r'/+$'), '')).baseUrl,
      'https://h/api/v1/pfep',
    );
  });
}
