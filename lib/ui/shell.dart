import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../data/providers.dart';
import '../models/models.dart';
import 'widgets/common.dart';

class NavItem {
  const NavItem(this.route, this.label, this.icon, {this.group = '', this.short});

  final String route;
  final String label;
  final IconData icon;
  final String group;

  /// Bottom-bar caption on a phone.
  final String? short;

  String get shortLabel => short ?? label.split(' ').first;
}

/// Navigation is per role (BRD 4.11) - a collector never sees the admin setup
/// screens, and management gets a read-only slice.
List<NavItem> navFor(String role) => switch (role) {
      'Collector' => const [
          NavItem('/work', 'My Assignments', Icons.assignment_outlined, group: 'My Work', short: 'Work'),
          NavItem('/collect', 'Collect Data', Icons.photo_camera_outlined, group: 'My Work', short: 'Collect'),
          NavItem('/records', 'My Submissions', Icons.list_alt_outlined, group: 'My Work', short: 'Submitted'),
          NavItem('/sync', 'Offline Sync', Icons.sync_outlined, group: 'My Work', short: 'Sync'),
        ],
      'Reviewer' => const [
          NavItem('/dashboard', 'Progress Dashboard', Icons.grid_view_outlined, group: 'Review'),
          NavItem('/review', 'Review Queue', Icons.visibility_outlined, group: 'Review'),
          NavItem('/records', 'PFEP Records', Icons.list_alt_outlined, group: 'Review'),
          NavItem('/export', 'Excel Export', Icons.description_outlined, group: 'Output'),
          NavItem('/labels', 'Label Studio', Icons.sell_outlined, group: 'Output'),
          NavItem('/audit', 'Audit Trail', Icons.shield_outlined, group: 'Output'),
        ],
      'Viewer' => const [
          NavItem('/dashboard', 'Progress Dashboard', Icons.grid_view_outlined, group: 'Management View'),
          NavItem('/records', 'PFEP Records', Icons.list_alt_outlined, group: 'Management View'),
          NavItem('/export', 'Excel Export', Icons.description_outlined, group: 'Management View'),
        ],
      _ => const [
          NavItem('/dashboard', 'Progress Dashboard', Icons.grid_view_outlined, group: 'Overview'),
          NavItem('/customers', 'Customers / Projects', Icons.layers_outlined, group: 'Overview'),
          NavItem('/part-master', 'Part Master', Icons.storage_outlined, group: 'Setup'),
          NavItem('/vendors', 'Vendors', Icons.local_shipping_outlined, group: 'Setup'),
          NavItem('/field-config', 'Field Config', Icons.tune_outlined, group: 'Setup'),
          // Sits in Setup, not Output: it configures what Label Studio prints
          // rather than printing anything, the same way Field Config shapes the
          // collection form (BRD 4.8).
          NavItem('/label-formats', 'Label Formats', Icons.crop_free_outlined, group: 'Setup'),
          NavItem('/users', 'Users & Roles', Icons.people_outline, group: 'Setup'),
          NavItem('/records', 'PFEP Records', Icons.list_alt_outlined, group: 'Data'),
          NavItem('/review', 'Review Queue', Icons.visibility_outlined, group: 'Data'),
          NavItem('/export', 'Excel Export', Icons.description_outlined, group: 'Output'),
          NavItem('/labels', 'Label Studio', Icons.sell_outlined, group: 'Output'),
          NavItem('/audit', 'Audit Trail', Icons.shield_outlined, group: 'Output'),
        ],
    };

const _sideWidth = 248.0;
const _topHeight = 64.0;

class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child, required this.location});

  final Widget child;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    if (user == null) {
      return const AmbientBackground(child: Scaffold(body: Center(child: Loading())));
    }

    final items = navFor(ref.watch(effectiveRoleProvider));
    final wide = MediaQuery.sizeOf(context).width >= 1000;

    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        drawer: wide
            ? null
            : Drawer(
                backgroundColor: Colors.transparent,
                width: 262,
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: Brand.sideFill),
                  child: _Sidebar(items: items, location: location, user: user, inDrawer: true),
                ),
              ),
        body: Row(children: [
          if (wide)
            Container(
              width: _sideWidth,
              decoration: BoxDecoration(
                gradient: Brand.sideFill,
                border: Border(right: BorderSide(color: Brand.line)),
              ),
              child: _Sidebar(items: items, location: location, user: user),
            ),
          Expanded(
            child: Column(children: [
              _TopBar(user: user, wide: wide),
              const _OfflineBanner(),
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  // #canvas { padding: 26px 26px 40px } / #screens { max-width:1420 }
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1420),
                    child: child,
                  ),
                ),
              ),
            ]),
          ),
        ]),
        bottomNavigationBar:
            wide || items.length > 5 ? null : _BottomNav(items: items, location: location),
      ),
    );
  }
}

/* ------------------------------------------------------------------ sidebar */

class _Sidebar extends ConsumerWidget {
  const _Sidebar({
    required this.items,
    required this.location,
    required this.user,
    this.inDrawer = false,
  });

  final List<NavItem> items;
  final String location;
  final AppUser user;
  final bool inDrawer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queued = ref.watch(queueCountProvider).value ?? 0;
    final review = ref.watch(reviewQueueProvider).value?.length ?? 0;

    final groups = <String, List<NavItem>>{};
    for (final i in items) {
      groups.putIfAbsent(i.group, () => []).add(i);
    }

    return SafeArea(
      bottom: false,
      child: Column(children: [
        // .brandrow
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Brand.line)),
          ),
          child: Row(children: [
            Image.asset('assets/brand/vistar_s.png',
                width: 34, height: 36, errorBuilder: (_, _, _) => const SizedBox(width: 34)),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text('Vistar PFEP', style: display(size: 17)),
                const SizedBox(height: 2),
                Text('PLAN FOR EVERY PART', style: eyebrow(size: 10, tracking: 1.2)),
              ]),
            ),
          ]),
        ),
        // #nav
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
            children: [
              for (final entry in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 14, 10, 8),
                  child: Text(entry.key.toUpperCase(), style: eyebrow()),
                ),
                for (final item in entry.value)
                  _NavTile(
                    item: item,
                    selected: location == item.route || location.startsWith('${item.route}/'),
                    count: switch (item.route) {
                      '/sync' => queued == 0 ? null : '$queued',
                      '/review' => review == 0 ? null : '$review',
                      '/records' => ref.watch(recordsProvider).value?.length.toString(),
                      _ => null,
                    },
                    onTap: () {
                      if (inDrawer) Navigator.of(context).pop();
                      context.go(item.route);
                    },
                  ),
              ],
            ],
          ),
        ),
        // .sidefoot
        Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: Brand.line))),
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
          child: SafeArea(
            top: false,
            child: Row(children: [
              Avatar(user.initials, size: 34),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: body(size: 12.8, weight: FontWeight.w700, height: 1.25)),
                  Text('${user.role}${user.empCode == null ? '' : ' · ${user.empCode}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: body(size: 10.5, weight: FontWeight.w600, color: Brand.txt3)),
                ]),
              ),
              IconButton(
                tooltip: 'Sign out',
                iconSize: 17,
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(),
                color: Brand.txt3,
                hoverColor: Brand.bad.withValues(alpha: 0.1),
                icon: Icon(Icons.logout),
                onPressed: () => ref.read(sessionProvider.notifier).signOut(),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

/// `.nav` — 11px radius, and when active a ribbon tick bleeding off the left
/// edge plus a pink-to-purple wash.
class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.selected, required this.onTap, this.count});

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;
  final String? count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Stack(clipBehavior: Clip.none, children: [
          if (selected)
            Positioned(
              left: -12,
              top: 7,
              bottom: 7,
              child: Container(
                width: 3,
                decoration: BoxDecoration(
                  gradient: Brand.ribbon,
                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
                ),
              ),
            ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(11),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: selected ? Brand.navOnFill : null,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: selected ? Brand.pink.withValues(alpha: 0.16) : Colors.transparent,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                  child: Row(children: [
                    Opacity(
                      opacity: 0.85,
                      child: Icon(item.icon, size: 17, color: selected ? Brand.txt : Brand.txt2),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(item.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: body(
                            size: 13.2,
                            weight: selected ? FontWeight.w700 : FontWeight.w600,
                            color: selected ? Brand.txt : Brand.txt2,
                          )),
                    ),
                    if (count != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: selected ? Brand.pink.withValues(alpha: 0.24) : Brand.txt3.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(count!,
                            style: body(
                              size: 10.5,
                              weight: FontWeight.w800,
                              color: selected ? const Color(0xFFFBC7E2) : Brand.txt2,
                            )),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      );
}

/* ------------------------------------------------------------------- topbar */

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.user, required this.wide});

  final AppUser user;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final online = ref.watch(connectivityProvider);
    final queued = ref.watch(queueCountProvider).value ?? 0;
    final light = ref.watch(themeModeProvider);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: Brand.topFill,
            border: Border(bottom: BorderSide(color: Brand.line)),
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: _topHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  if (!wide)
                    Builder(
                      builder: (ctx) => IconButton(
                        icon: Icon(Icons.menu, size: 21),
                        onPressed: () => Scaffold.of(ctx).openDrawer(),
                      ),
                    ),
                  if (wide) const _GlobalSearch(),
                  const Spacer(),
                  if (wide && session.customers.isNotEmpty) ...[
                    const _CustomerPicker(),
                    const SizedBox(width: 12),
                  ],
                  if (!wide && session.customers.isNotEmpty)
                    const Flexible(child: _CustomerPicker(compact: true)),
                  if (wide) ...[
                    _NetPill(online: online, queued: queued),
                    const SizedBox(width: 12),
                  ],
                  _IconBtn(
                    icon: light ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                    tooltip: light ? 'Switch to dark' : 'Switch to light',
                    onTap: () => ref.read(themeModeProvider.notifier).toggle(),
                  ),
                  if (wide && user.isAdmin) ...[
                    const SizedBox(width: 12),
                    const _RoleSwitch(),
                  ],
                  const SizedBox(width: 12),
                  _IconBtn(
                    icon: Icons.notifications_none_rounded,
                    tooltip: 'Needs attention',
                    dot: queued > 0 || !online,
                    onTap: () => _showNotifications(context, ref),
                  ),
                  const SizedBox(width: 12),
                  _AccountButton(user: user, wide: wide),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showNotifications(BuildContext context, WidgetRef ref) {
    final queued = ref.read(queueCountProvider).value ?? 0;
    final online = ref.read(connectivityProvider);
    final review = ref.read(reviewQueueProvider).value?.length ?? 0;
    final dash = ref.read(dashboardProvider).value;

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Needs attention'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!online)
              AlertBox(
                tone: AlertTone.warn,
                title: 'Working offline',
                message: 'Captured data is held on this device and uploads automatically.',
              ),
            if (queued > 0) ...[
              const SizedBox(height: 10),
              AlertBox(
                tone: AlertTone.info,
                title: '$queued item(s) waiting to sync',
                message: 'Open Offline Sync to push them now.',
              ),
            ],
            if (review > 0) ...[
              const SizedBox(height: 10),
              AlertBox(
                tone: AlertTone.warn,
                title: '$review record(s) waiting for review',
                message: 'The field team has submitted work that needs sign-off.',
              ),
            ],
            if ((dash?.totals.missingPhotoItems ?? 0) > 0) ...[
              const SizedBox(height: 10),
              AlertBox(
                tone: AlertTone.bad,
                title: '${dash!.totals.missingPhotoItems} record(s) missing a photograph',
                message: 'They cannot be submitted until every photo type is captured.',
              ),
            ],
            if (online && queued == 0 && review == 0 && (dash?.totals.missingPhotoItems ?? 0) == 0)
              AlertBox(
                tone: AlertTone.ok,
                title: 'Nothing needs attention',
                message: 'Everything is synced and nothing is waiting for review.',
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Close')),
        ],
      ),
    );
  }
}

/// `.searchbox` — jumps straight to a part or vendor in the records list.
class _GlobalSearch extends ConsumerStatefulWidget {
  const _GlobalSearch();

  @override
  ConsumerState<_GlobalSearch> createState() => _GlobalSearchState();
}

class _GlobalSearchState extends ConsumerState<_GlobalSearch> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String v) {
    final q = v.trim();
    if (q.isEmpty) return;
    ref.read(recordFilterProvider.notifier).set(RecordFilter(query: q));
    context.go('/records');
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width * 0.38;
    return SizedBox(
      width: width.clamp(200.0, 330.0),
      height: 38,
      child: TextField(
        controller: _controller,
        textInputAction: TextInputAction.search,
        onSubmitted: _submit,
        style: body(size: 13),
        decoration: InputDecoration(
          hintText: 'Search part, vendor...',
          prefixIcon: Icon(Icons.search, size: 17, color: Brand.txt3),
          prefixIconConstraints: const BoxConstraints(minWidth: 36),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        ),
      ),
    );
  }
}

/// `.exercise-pick` — the customer/project selector.
class _CustomerPicker extends ConsumerWidget {
  const _CustomerPicker({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final active = session.activeCustomer;
    if (active == null) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      tooltip: 'Switch customer / project',
      offset: const Offset(0, 44),
      itemBuilder: (_) => [
        for (final c in session.customers)
          PopupMenuItem(
            value: c.id,
            child: Row(children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: c.status == 'Live' ? Brand.ok : Brand.txt3,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.name, style: body(size: 12.5, weight: FontWeight.w700)),
                  Text('${c.id} · ${c.program ?? 'no programme'} · ${c.totalRecords} line items',
                      style: body(size: 10.5, color: Brand.txt3)),
                ]),
              ),
            ]),
          ),
      ],
      onSelected: (id) => ref.read(sessionProvider.notifier).setCustomer(id),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Brand.surface,
          border: Border.all(color: Brand.line),
          borderRadius: BorderRadius.circular(Brand.rSm),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!compact) ...[
            Text('CUSTOMER', style: eyebrow(size: 10, tracking: 0.8)),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Text(
              '${active.id}${active.program == null ? '' : ' · ${active.program}'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: body(size: 12.5, weight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.expand_more, size: 15, color: Brand.txt3),
        ]),
      ),
    );
  }
}

/// `.netpill`
class _NetPill extends ConsumerWidget {
  const _NetPill({required this.online, required this.queued});

  final bool online;
  final int queued;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tone = online ? Brand.ok : Brand.warn;
    final label = online ? (queued > 0 ? '$queued to sync' : 'Online') : 'Offline';
    return InkWell(
      onTap: () => ref.read(connectivityProvider.notifier).check(),
      borderRadius: BorderRadius.circular(Brand.rSm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: online ? Brand.surface : Brand.warn.withValues(alpha: 0.08),
          border: Border.all(color: online ? Brand.line : Brand.warn.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(Brand.rSm),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: tone,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: tone, blurRadius: 8)],
            ),
          ),
          const SizedBox(width: 7),
          Text(label, style: body(size: 12, weight: FontWeight.w700, color: tone)),
        ]),
      ),
    );
  }
}

/// `#roleswitch` — lets an admin preview the app as another role would see it.
///
/// This changes the navigation and screens only. Every request is still made as
/// the signed-in admin and the API enforces the real permissions, so it is a
/// layout preview for training and demos, not a privilege change.
class _RoleSwitch extends ConsumerWidget {
  const _RoleSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewAs = ref.watch(effectiveRoleProvider);
    return PopupMenuButton<String>(
      tooltip: 'Preview the app as another role',
      offset: const Offset(0, 44),
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: SizedBox(
            width: 230,
            child: Text(
              'Preview the layout another role sees. Permissions do not change - '
              'the API still answers as you.',
              style: body(size: 11, color: Brand.txt3, height: 1.45),
            ),
          ),
        ),
        const PopupMenuDivider(),
        for (final r in ['Admin', 'Collector', 'Reviewer', 'Viewer'])
          PopupMenuItem(
            value: r,
            child: Row(children: [
              if (r == viewAs)
                Icon(Icons.check, size: 15, color: Brand.pink)
              else
                const SizedBox(width: 15),
              const SizedBox(width: 9),
              Text(r, style: body(size: 12.5, weight: FontWeight.w700)),
            ]),
          ),
      ],
      onSelected: (r) => ref.read(effectiveRoleProvider.notifier).set(r),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Brand.surface,
          border: Border.all(color: Brand.line),
          borderRadius: BorderRadius.circular(Brand.rSm),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('VIEW AS', style: eyebrow(size: 10, tracking: 0.8)),
          const SizedBox(width: 8),
          Text(viewAs, style: body(size: 12.5, weight: FontWeight.w700)),
          const SizedBox(width: 4),
          Icon(Icons.expand_more, size: 15, color: Brand.txt3),
        ]),
      ),
    );
  }
}

/// `.iconbtn`
class _IconBtn extends StatelessWidget {
  const _IconBtn({required this.icon, required this.onTap, this.tooltip, this.dot = false});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final btn = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Brand.rSm),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Brand.surface,
          border: Border.all(color: Brand.line),
          borderRadius: BorderRadius.circular(Brand.rSm),
        ),
        child: Stack(children: [
          Center(child: Icon(icon, size: 17, color: Brand.txt2)),
          if (dot)
            Positioned(
              top: 7,
              right: 8,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: Brand.pink,
                  shape: BoxShape.circle,
                  border: Border.all(color: Brand.bg2, width: 2),
                ),
              ),
            ),
        ]),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

class _AccountButton extends ConsumerWidget {
  const _AccountButton({required this.user, required this.wide});

  final AppUser user;
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) => PopupMenuButton<String>(
        tooltip: user.name,
        offset: const Offset(0, 46),
        itemBuilder: (_) => [
          PopupMenuItem(
            enabled: false,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user.name, style: body(size: 13, weight: FontWeight.w700)),
              Text('${user.role} · ${user.empCode ?? user.username}',
                  style: body(size: 11, color: Brand.txt3)),
              if (user.device != null)
                Text(user.device!, style: body(size: 10.5, color: Brand.txt3)),
            ]),
          ),
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'signout', child: Text('Sign out')),
        ],
        onSelected: (v) {
          if (v == 'signout') ref.read(sessionProvider.notifier).signOut();
        },
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Avatar(user.initials, size: 34),
          if (wide) ...[
            const SizedBox(width: 9),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(user.name, style: body(size: 12.5, weight: FontWeight.w700)),
              Text(user.role, style: body(size: 10.5, color: Brand.txt3)),
            ]),
          ],
        ]),
      );
}

class _BottomNav extends ConsumerWidget {
  const _BottomNav({required this.items, required this.location});

  final List<NavItem> items;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = items.indexWhere((i) => location == i.route || location.startsWith('${i.route}/'));
    final queued = ref.watch(queueCountProvider).value ?? 0;

    return NavigationBar(
      height: 62,
      selectedIndex: idx < 0 ? 0 : idx,
      onDestinationSelected: (i) => context.go(items[i].route),
      destinations: [
        for (final item in items)
          NavigationDestination(
            icon: item.route == '/sync' && queued > 0
                ? Badge(label: Text('$queued'), child: Icon(item.icon, size: 20))
                : Icon(item.icon, size: 20),
            label: item.shortLabel,
          ),
      ],
    );
  }
}

class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(connectivityProvider);
    if (online) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Brand.warn.withValues(alpha: 0.13),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
      child: Row(children: [
        Icon(Icons.cloud_off_rounded, size: 15, color: Brand.warn),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'Working offline - data and photos are saved on this device and upload automatically '
            'when the connection returns.',
            style: body(size: 11.5, color: Brand.warn, height: 1.4),
          ),
        ),
        TextButton(
          onPressed: () => ref.read(connectivityProvider.notifier).check(),
          child: Text('Retry'),
        ),
      ]),
    );
  }
}
