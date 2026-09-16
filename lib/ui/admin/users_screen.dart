import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// BRD 4.11 - user roles and access.
///
/// Admin sets up and exports; Field Collectors only enter data for the customers
/// assigned to them; Reviewers approve; Management gets a read-only view.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  static const _roleBlurb = {
    'Admin': 'Upload part master, create customers, manage users, configure fields and labels, full export',
    'Collector': 'Enter data and capture photos, only for the customers assigned to them',
    'Reviewer': 'Review and approve submitted records before they reach the export',
    'Viewer': 'Read-only dashboard and export access for management',
  };

  static final _roleColor = {
    'Admin': Brand.violet,
    'Collector': Brand.pink,
    'Reviewer': Brand.orange,
    'Viewer': Brand.info,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);
    final customers = ref.watch(sessionProvider).customers;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
      children: [
        PageHeader(
          crumb: 'Setup ·',
          accent: 'Users',
          title: 'Users & role-based access',
          blurb: 'Customer PFEP data is confidential, so every action is behind a role. A collector scoped to '
              'a customer sees only that project on their phone, and every entry is stamped with who made it.',
          actions: [
            FilledButton.icon(
              onPressed: () => _edit(context, ref, null, customers),
              icon: Icon(Icons.person_add_alt, size: 17),
              label: Text('Add user'),
            ),
          ],
        ),
        Wrap(spacing: 12, runSpacing: 12, children: [
          for (final entry in _roleBlurb.entries)
            SizedBox(
              width: 300,
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
                decoration: BoxDecoration(
                  color: Brand.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Brand.line),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Pill(entry.key, color: _roleColor[entry.key]!),
                  const SizedBox(height: 8),
                  Text(entry.value,
                      style: TextStyle(color: Brand.txt3, fontSize: 11.5, height: 1.5)),
                ]),
              ),
            ),
        ]),
        const SizedBox(height: 20),
        users.when(
          loading: () => const Loading(),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(usersProvider)),
          data: (list) => ScrollTable(
            columns: const [
              DataColumn(label: Text('NAME')),
              DataColumn(label: Text('USERNAME')),
              DataColumn(label: Text('EMP CODE')),
              DataColumn(label: Text('ROLE')),
              DataColumn(label: Text('CUSTOMERS')),
              DataColumn(label: Text('DEVICE')),
              DataColumn(label: Text('ACTIVE')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final u in list)
                DataRow(cells: [
                  DataCell(Row(children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(gradient: Brand.ribbonSoft, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text(u.initials,
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Colors.white)),
                    ),
                    const SizedBox(width: 9),
                    Text(u.name, style: TextStyle(fontWeight: FontWeight.w600)),
                  ])),
                  DataCell(Text(u.username, style: mono(size: 11.5, color: Brand.txt2))),
                  DataCell(Text(u.empCode ?? '-', style: mono(size: 11.5, color: Brand.txt3))),
                  DataCell(Pill(u.role, color: _roleColor[u.role] ?? Brand.txt3)),
                  DataCell(Text(u.customers.isEmpty ? 'all' : u.customers.join(', '),
                      style: TextStyle(fontSize: 11.8, color: Brand.txt2))),
                  DataCell(Text(u.device ?? '-', style: mono(size: 10.5, color: Brand.txt3))),
                  DataCell(u.active
                      ? Icon(Icons.check_circle, size: 15, color: Brand.ok)
                      : Icon(Icons.block, size: 15, color: Brand.txt3)),
                  DataCell(IconButton(
                    icon: Icon(Icons.edit_outlined, size: 15),
                    onPressed: () => _edit(context, ref, u, customers),
                  )),
                ]),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, AppUser? existing, List<Customer> customers) async {
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _UserDialog(existing: existing, customers: customers),
    );
    if (body == null) return;
    try {
      final repo = ref.read(repositoryProvider);
      if (existing == null) {
        await repo.createUser(body);
      } else {
        await repo.updateUser(existing.id, body);
      }
      ref.invalidate(usersProvider);
      if (context.mounted) showToast(context, existing == null ? 'User created' : 'User updated');
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, 'Could not save', detail: e.message, error: true);
    }
  }
}

class _UserDialog extends StatefulWidget {
  const _UserDialog({this.existing, required this.customers});

  final AppUser? existing;
  final List<Customer> customers;

  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  late final _username = TextEditingController(text: widget.existing?.username ?? '');
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _emp = TextEditingController(text: widget.existing?.empCode ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _device = TextEditingController(text: widget.existing?.device ?? '');
  final _password = TextEditingController();
  late String _role = widget.existing?.role ?? 'Collector';
  late bool _active = widget.existing?.active ?? true;
  late final Set<String> _scope = {...(widget.existing?.customers ?? const [])};

  @override
  void dispose() {
    for (final c in [_username, _name, _emp, _phone, _device, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.existing == null ? 'Add user' : 'Edit ${widget.existing!.name}'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.existing == null)
                TextField(
                  controller: _username,
                  style: mono(size: 13),
                  decoration: const InputDecoration(labelText: 'Username'),
                ),
              const SizedBox(height: 12),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: TextField(controller: _emp, decoration: const InputDecoration(labelText: 'Employee code'))),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _phone, decoration: const InputDecoration(labelText: 'Phone'))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _role,
                    dropdownColor: Brand.surface2,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(value: 'Admin', child: Text('Admin')),
                      DropdownMenuItem(value: 'Collector', child: Text('Field Collector')),
                      DropdownMenuItem(value: 'Reviewer', child: Text('Reviewer / Supervisor')),
                      DropdownMenuItem(value: 'Viewer', child: Text('Viewer (management)')),
                    ],
                    onChanged: (v) => setState(() => _role = v ?? 'Collector'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _device, decoration: const InputDecoration(labelText: 'Device'))),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: widget.existing == null ? 'Password' : 'New password (optional)',
                ),
              ),
              if (_role == 'Collector') ...[
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Customers this collector may work on',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: Brand.txt2)),
                ),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final c in widget.customers)
                    FilterChip(
                      label: Text('${c.id}  ${c.program ?? ''}', style: TextStyle(fontSize: 11.5)),
                      selected: _scope.contains(c.id),
                      selectedColor: Brand.pink.withValues(alpha: 0.2),
                      onSelected: (v) => setState(() => v ? _scope.add(c.id) : _scope.remove(c.id)),
                    ),
                ]),
              ],
              const SizedBox(height: 6),
              SwitchListTile(
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                contentPadding: EdgeInsets.zero,
                dense: true,
                activeThumbColor: Brand.ok,
                title: Text('Active', style: TextStyle(fontSize: 12.5)),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop({
              if (widget.existing == null) 'username': _username.text.trim(),
              'name': _name.text.trim(),
              'role': _role,
              'empCode': _emp.text.trim(),
              'phone': _phone.text.trim(),
              'device': _device.text.trim(),
              'active': _active,
              if (_password.text.isNotEmpty) 'password': _password.text,
              'customers': _role == 'Collector' ? _scope.toList() : <String>[],
            }),
            child: Text(widget.existing == null ? 'Create' : 'Save'),
          ),
        ],
      );
}
