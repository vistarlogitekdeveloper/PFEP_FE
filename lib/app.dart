import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/theme.dart';
import 'data/providers.dart';
import 'ui/admin/audit_screen.dart';
import 'ui/admin/customers_screen.dart';
import 'ui/admin/dashboard_screen.dart';
import 'ui/admin/export_screen.dart';
import 'ui/admin/field_config_screen.dart';
import 'ui/admin/label_formats_screen.dart';
import 'ui/admin/labels_screen.dart';
import 'ui/admin/part_master_screen.dart';
import 'ui/admin/users_screen.dart';
import 'ui/admin/vendors_screen.dart';
import 'ui/collector/collect_screen.dart';
import 'ui/collector/my_work_screen.dart';
import 'ui/collector/sync_screen.dart';
import 'ui/login_screen.dart';
import 'ui/records/record_detail_screen.dart';
import 'ui/records/records_screen.dart';
import 'ui/reviewer/review_queue_screen.dart';
import 'ui/shell.dart';

/// Home route per role (BRD 4.11): a collector lands on their work list, a
/// manager on the progress dashboard.
String homeFor(String? role) => switch (role) {
      'Collector' => '/work',
      _ => '/dashboard',
    };

class PfepApp extends ConsumerStatefulWidget {
  const PfepApp({super.key});

  @override
  ConsumerState<PfepApp> createState() => _PfepAppState();
}

class _PfepAppState extends ConsumerState<PfepApp> {
  late final GoRouter _router;
  final _authChanged = _Bumper();

  @override
  void initState() {
    super.initState();

    // listenManual (rather than ref.listen) because this subscription lives for
    // the router's lifetime, not one build pass.
    ref.listenManual(sessionProvider, (prev, next) {
      if (prev?.signedIn != next.signedIn || prev?.loading != next.loading) {
        _authChanged.bump();
      }
    });

    _router = GoRouter(
      initialLocation: '/dashboard',
      refreshListenable: _authChanged,
      redirect: (context, state) {
        final session = ref.read(sessionProvider);
        if (session.loading) return null;

        final goingToLogin = state.matchedLocation == '/login';
        if (!session.signedIn) return goingToLogin ? null : '/login';
        if (goingToLogin) return homeFor(session.user!.role);

        // Keep each role out of screens it has no business on.
        final role = session.user!.role;
        final loc = state.matchedLocation;
        final blocked = switch (role) {
          // A collector enters data for their own assignments only (BRD 4.11) —
          // including the manager dashboard, which is the app's initial route.
          'Collector' => const ['/dashboard', '/customers', '/part-master', '/vendors', '/field-config', '/label-formats', '/users', '/audit', '/export', '/labels', '/review'],
          'Reviewer' => const ['/part-master', '/vendors', '/field-config', '/label-formats', '/users', '/work', '/collect', '/sync'],
          'Viewer' => const ['/part-master', '/vendors', '/field-config', '/label-formats', '/users', '/work', '/collect', '/sync', '/review', '/labels'],
          // Admin reaches everything, including the collector screens, so the
          // "view as" preview in the top bar can walk those layouts.
          _ => const <String>[],
        };
        if (blocked.any((b) => loc == b || loc.startsWith('$b/'))) return homeFor(role);
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
        ShellRoute(
          builder: (context, state, child) => AppShell(location: state.matchedLocation, child: child),
          routes: [
            GoRoute(path: '/dashboard', builder: (_, _) => const DashboardScreen()),
            GoRoute(path: '/customers', builder: (_, _) => const CustomersScreen()),
            GoRoute(path: '/part-master', builder: (_, _) => const PartMasterScreen()),
            GoRoute(path: '/vendors', builder: (_, _) => const VendorsScreen()),
            GoRoute(path: '/field-config', builder: (_, _) => const FieldConfigScreen()),
            GoRoute(path: '/label-formats', builder: (_, _) => const LabelFormatsScreen()),
            GoRoute(path: '/users', builder: (_, _) => const UsersScreen()),
            GoRoute(path: '/records', builder: (_, _) => const RecordsScreen()),
            GoRoute(
              path: '/records/:id',
              builder: (_, state) => RecordDetailScreen(recordId: state.pathParameters['id']!),
            ),
            GoRoute(path: '/review', builder: (_, _) => const ReviewQueueScreen()),
            GoRoute(path: '/export', builder: (_, _) => const ExportScreen()),
            GoRoute(path: '/labels', builder: (_, _) => const LabelsScreen()),
            GoRoute(path: '/audit', builder: (_, _) => const AuditScreen()),
            GoRoute(path: '/work', builder: (_, _) => const MyWorkScreen()),
            GoRoute(
              path: '/collect',
              builder: (_, state) => CollectScreen(recordId: state.uri.queryParameters['record']),
            ),
            GoRoute(path: '/sync', builder: (_, _) => const SyncScreen()),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Watch so a sign-in/sign-out rebuilds and the redirect re-runs.
    ref.watch(sessionProvider);
    // buildTheme() also sets Brand.isLight, and runs before the subtree below
    // rebuilds, so every screen reads the palette for the mode being applied.
    final light = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Vistar PFEP',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(light: light),
      routerConfig: _router,
      // Brand tokens are read as plain values rather than through
      // Theme.of(context), so a screen that never touches the inherited theme
      // would keep painting the old palette. Re-keying the subtree on the mode
      // forces every screen to rebuild against the palette now in effect.
      builder: (context, child) => KeyedSubtree(
        key: ValueKey(light),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}

/// Bridges the Riverpod session into GoRouter's refresh mechanism.
class _Bumper extends ChangeNotifier {
  void bump() => notifyListeners();
}
