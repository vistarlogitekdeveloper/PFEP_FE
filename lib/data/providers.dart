import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/offline_queue.dart';
import '../models/models.dart';
import 'repository.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

/* --------------------------------------------------------------- appearance */

/// Light / dark, as the prototype's `body.light` toggle. Persisted so the
/// choice survives a restart.
class ThemeModeNotifier extends Notifier<bool> {
  static const _key = 'pfep.theme.light';

  @override
  bool build() {
    unawaited(_restore());
    return false;
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final light = prefs.getBool(_key);
    if (light != null && light != state) state = light;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, state);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, bool>(ThemeModeNotifier.new);

/// The role whose navigation and screens are currently rendered.
///
/// Normally this is just the signed-in role. An Admin can preview another
/// role's layout from the top bar; that changes what is *shown*, never what is
/// permitted - every request still goes out as the real user and the API
/// enforces the real role.
class EffectiveRoleNotifier extends Notifier<String> {
  String? _override;

  @override
  String build() {
    final role = ref.watch(sessionProvider.select((s) => s.user?.role)) ?? 'Viewer';
    if (role != 'Admin') _override = null;
    return _override ?? role;
  }

  void set(String role) {
    final real = ref.read(sessionProvider).user?.role;
    if (real != 'Admin') return;
    _override = role == real ? null : role;
    state = role;
  }
}

final effectiveRoleProvider =
    NotifierProvider<EffectiveRoleNotifier, String>(EffectiveRoleNotifier.new);

final repositoryProvider = Provider<PfepRepository>((ref) => PfepRepository(ref.watch(apiClientProvider)));

/* ------------------------------------------------------------------ session */

class SessionState {
  const SessionState({
    this.user,
    this.customers = const [],
    this.activeCustomerId,
    this.loading = true,
    this.error,
  });

  final AppUser? user;
  final List<Customer> customers;
  final String? activeCustomerId;
  final bool loading;
  final String? error;

  bool get signedIn => user != null;

  Customer? get activeCustomer {
    if (customers.isEmpty) return null;
    return customers.firstWhere(
      (c) => c.id == activeCustomerId,
      orElse: () => customers.first,
    );
  }

  SessionState copyWith({
    AppUser? user,
    List<Customer>? customers,
    String? activeCustomerId,
    bool? loading,
    String? error,
    bool clearUser = false,
    bool clearError = false,
  }) =>
      SessionState(
        user: clearUser ? null : (user ?? this.user),
        customers: customers ?? this.customers,
        activeCustomerId: activeCustomerId ?? this.activeCustomerId,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

class SessionNotifier extends Notifier<SessionState> {
  static const _tokenKey = 'pfep.auth.token';
  static const _customerKey = 'pfep.active.customer';

  PfepRepository get _repo => ref.read(repositoryProvider);
  ApiClient get _api => ref.read(apiClientProvider);

  @override
  SessionState build() {
    unawaited(restore());
    return const SessionState();
  }

  /// Re-uses a saved token so the field team is not asked to sign in every
  /// time the app is reopened at a vendor site.
  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final customerId = prefs.getString(_customerKey);
    await OfflineQueue.instance.load();

    if (token == null) {
      state = state.copyWith(loading: false);
      return;
    }
    _api.setToken(token);
    try {
      final me = await _repo.me();
      state = SessionState(
        user: me.user,
        customers: me.customers,
        activeCustomerId: customerId ?? (me.customers.isEmpty ? null : me.customers.first.id),
        loading: false,
      );
    } catch (e) {
      // An expired token or an unreachable server must not trap the user on a
      // spinner; drop the token and show the sign-in screen.
      _api.setToken(null);
      await prefs.remove(_tokenKey);
      state = state.copyWith(loading: false, clearUser: true);
    }
  }

  Future<void> signIn(String username, String password) async {
    state = state.copyWith(loading: true, clearError: true);
    try {
      final res = await _repo.login(username, password, device: _deviceLabel());
      _api.setToken(res.token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, res.token);

      final me = await _repo.me();
      final saved = prefs.getString(_customerKey);
      final active = me.customers.any((c) => c.id == saved)
          ? saved
          : (me.customers.isEmpty ? null : me.customers.first.id);

      state = SessionState(user: me.user, customers: me.customers, activeCustomerId: active, loading: false);
    } on ApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    _api.setToken(null);
    state = const SessionState(loading: false);
  }

  Future<void> setCustomer(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_customerKey, id);
    state = state.copyWith(activeCustomerId: id);
    ref.invalidate(dashboardProvider);
    ref.invalidate(myWorkProvider);
    ref.invalidate(reviewQueueProvider);
    ref.invalidate(recordsProvider);
    ref.invalidate(fieldConfigProvider);
  }

  Future<void> refreshCustomers() async {
    try {
      final list = await _repo.customers();
      state = state.copyWith(customers: list);
    } catch (_) {
      // keep the cached list; the banner already tells the user we are offline
    }
  }

  String _deviceLabel() {
    if (kIsWeb) return 'WEB';
    return defaultTargetPlatform.name.toUpperCase();
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

final activeCustomerIdProvider = Provider<String?>((ref) => ref.watch(sessionProvider).activeCustomerId);

/* ------------------------------------------------------------- connectivity */

/// Polls the API so the UI can show an honest online/offline pill and flush
/// the offline queue the moment a connection returns.
class ConnectivityNotifier extends Notifier<bool> {
  Timer? _timer;

  @override
  bool build() {
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => check());
    ref.onDispose(() => _timer?.cancel());
    unawaited(check());
    return true;
  }

  Future<bool> check() async {
    if (ref.read(sessionProvider).user == null) return state;
    final ok = await ref.read(repositoryProvider).ping();
    if (ok != state) state = ok;
    if (ok && OfflineQueue.instance.length > 0) {
      try {
        await ref.read(repositoryProvider).flushQueue();
        ref.invalidate(myWorkProvider);
        ref.invalidate(recordsProvider);
      } catch (_) {
        // stay queued; the sync screen has a manual retry
      }
    }
    return ok;
  }
}

final connectivityProvider = NotifierProvider<ConnectivityNotifier, bool>(ConnectivityNotifier.new);

final queueCountProvider = StreamProvider<int>((ref) {
  final controller = StreamController<int>();
  void emit() => controller.add(OfflineQueue.instance.length);
  OfflineQueue.instance.addListener(emit);
  emit();
  ref.onDispose(() {
    OfflineQueue.instance.removeListener(emit);
    controller.close();
  });
  return controller.stream;
});

/* ------------------------------------------------------------------- data */

final dashboardProvider = FutureProvider.autoDispose<Dashboard?>((ref) async {
  final cid = ref.watch(activeCustomerIdProvider);
  if (cid == null) return null;
  return ref.watch(repositoryProvider).dashboard(cid);
});

final myWorkProvider = FutureProvider.autoDispose<MyWork>((ref) async {
  final cid = ref.watch(activeCustomerIdProvider);
  return ref.watch(repositoryProvider).myWork(customerId: cid);
});

final reviewQueueProvider = FutureProvider.autoDispose<List<PfepRecord>>((ref) async {
  final cid = ref.watch(activeCustomerIdProvider);
  return ref.watch(repositoryProvider).reviewQueue(customerId: cid);
});

class RecordFilter {
  const RecordFilter({this.status, this.query, this.mine = false});

  final String? status;
  final String? query;
  final bool mine;

  @override
  bool operator ==(Object other) =>
      other is RecordFilter && other.status == status && other.query == query && other.mine == mine;

  @override
  int get hashCode => Object.hash(status, query, mine);
}

class RecordFilterNotifier extends Notifier<RecordFilter> {
  @override
  RecordFilter build() {
    // A collector's record list is always their own work - the screen is headed
    // "My submissions" and the sidebar badge counts the same rows. Defaulting it
    // here rather than in the screen's initState keeps the two in step on the
    // first frame; otherwise the badge counts the whole customer until the
    // screen has mounted and corrected the filter.
    //
    // `select` narrows the dependency to the role, so refreshing the customer
    // list does not throw away a filter the user has chosen.
    final isCollector =
        ref.watch(sessionProvider.select((s) => s.user?.isCollector ?? false));
    return RecordFilter(mine: isCollector);
  }

  void set(RecordFilter next) => state = next;
}

final recordFilterProvider =
    NotifierProvider<RecordFilterNotifier, RecordFilter>(RecordFilterNotifier.new);

final recordsProvider = FutureProvider.autoDispose<List<PfepRecord>>((ref) async {
  final cid = ref.watch(activeCustomerIdProvider);
  if (cid == null) return [];
  final f = ref.watch(recordFilterProvider);
  return ref.watch(repositoryProvider).records(cid, status: f.status, q: f.query, mine: f.mine);
});

final recordProvider = FutureProvider.autoDispose.family<PfepRecord, String>(
  (ref, id) => ref.watch(repositoryProvider).record(id),
);

final fieldConfigProvider = FutureProvider.autoDispose<FieldConfig?>((ref) async {
  final cid = ref.watch(activeCustomerIdProvider);
  if (cid == null) return null;
  return ref.watch(repositoryProvider).fieldConfig(cid);
});

/// BRD 4.3 - whether the server's optional vendor-distance lookup is switched
/// on, so the vendor screen offers the action or explains why it cannot.
final distanceStatusProvider = FutureProvider<DistanceStatus>(
  (ref) => ref.watch(repositoryProvider).distanceStatus(),
);

/// BRD 4.8 - the label formats for the active customer, with the tokens and
/// examples the editor previews against.
final labelTemplatesProvider = FutureProvider.autoDispose<LabelTemplateConfig?>((ref) async {
  final cid = ref.watch(activeCustomerIdProvider);
  if (cid == null) return null;
  return ref.watch(repositoryProvider).labelTemplates(cid);
});

final partSearchProvider = FutureProvider.autoDispose.family<List<Part>, String>((ref, q) async {
  final cid = ref.watch(activeCustomerIdProvider);
  if (cid == null) return [];
  return ref.watch(repositoryProvider).parts(cid, q: q.isEmpty ? null : q);
});

final vendorsProvider = FutureProvider.autoDispose<List<Vendor>>(
  (ref) => ref.watch(repositoryProvider).vendors(),
);

final usersProvider = FutureProvider.autoDispose<List<AppUser>>(
  (ref) => ref.watch(repositoryProvider).users(),
);

final auditProvider = FutureProvider.autoDispose.family<List<AuditEntry>, String?>((ref, q) async {
  final cid = ref.watch(activeCustomerIdProvider);
  return ref.watch(repositoryProvider).audit(customerId: cid, q: q);
});
