import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// Customers / projects. Creating one seeds its field configuration and label
/// templates from the default catalogue, so a new client is ready to collect
/// against immediately and is then tuned in Field Config.
class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
      children: [
        PageHeader(
          crumb: 'Setup ·',
          accent: 'Customers',
          title: 'Customers & projects',
          blurb: 'Each customer is a separate PFEP exercise with its own part master, field configuration, '
              'label formats and production plan. The plan per day and working days drive every '
              'consumption-based calculation.',
          actions: [
            FilledButton.icon(
              onPressed: () => _create(context, ref),
              icon: Icon(Icons.add, size: 17),
              label: Text('New customer'),
            ),
          ],
        ),
        if (session.customers.isEmpty)
          const EmptyState(message: 'No customers yet.', icon: Icons.layers_outlined)
        else
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final c in session.customers) _CustomerCard(customer: c),
            ],
          ),
      ],
    );
  }

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _CustomerDialog(),
    );
    if (body == null) return;
    try {
      await ref.read(repositoryProvider).createCustomer(body);
      await ref.read(sessionProvider.notifier).refreshCustomers();
      if (context.mounted) {
        showToast(context, 'Customer created',
            detail: 'Field config and label templates seeded - upload its part master next.');
      }
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, 'Could not create', detail: e.message, error: true);
    }
  }
}

class _CustomerCard extends ConsumerWidget {
  const _CustomerCard({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(activeCustomerIdProvider) == customer.id;
    return SizedBox(
      width: 360,
      child: InkWell(
        onTap: () => ref.read(sessionProvider.notifier).setCustomer(customer.id),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
          decoration: BoxDecoration(
            color: Brand.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: active ? Brand.pink.withValues(alpha: 0.5) : Brand.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(customer.id, style: mono(size: 12, color: Brand.pink)),
              const SizedBox(width: 8),
              Pill(customer.status, color: customer.status == 'Live' ? Brand.ok : Brand.txt3),
              const Spacer(),
              if (active) Pill('Active', color: Brand.pink, icon: Icons.check),
            ]),
            const SizedBox(height: 10),
            Text(customer.name,
                maxLines: 2,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, height: 1.3)),
            const SizedBox(height: 4),
            Text(
              '${customer.program ?? 'no programme'}  -  ${customer.planPerDay} veh/day  -  '
              '${customer.workDays} days/month',
              style: TextStyle(color: Brand.txt3, fontSize: 11.5),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Text('${customer.approved}/${customer.totalRecords} approved',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
              const Spacer(),
              Text('${customer.progressPct}% captured',
                  style: TextStyle(color: Brand.txt3, fontSize: 11.5)),
            ]),
            const SizedBox(height: 7),
            ProgressBar(
              value: customer.totalRecords == 0 ? 0 : customer.approved / customer.totalRecords,
              color: customer.status == 'Live' ? Brand.ok : Brand.txt3,
              height: 5,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Icon(Icons.event_outlined, size: 13, color: Brand.txt3),
              const SizedBox(width: 6),
              Text('${customer.startDate ?? '-'}  to  ${customer.targetDate ?? '-'}',
                  style: TextStyle(color: Brand.txt3, fontSize: 11)),
              const Spacer(),
              TextButton(
                onPressed: () => _edit(context, ref),
                style: TextButton.styleFrom(minimumSize: Size.zero, padding: const EdgeInsets.symmetric(horizontal: 6)),
                child: Text('Edit', style: TextStyle(fontSize: 11.5)),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _CustomerDialog(existing: customer),
    );
    if (body == null) return;
    try {
      await ref.read(repositoryProvider).updateCustomer(customer.id, body);
      await ref.read(sessionProvider.notifier).refreshCustomers();
      ref.invalidate(dashboardProvider);
      if (context.mounted) showToast(context, 'Customer updated');
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, 'Could not update', detail: e.message, error: true);
    }
  }
}

class _CustomerDialog extends StatefulWidget {
  const _CustomerDialog({this.existing});

  final Customer? existing;

  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  late final _id = TextEditingController(text: widget.existing?.id ?? '');
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _program = TextEditingController(text: widget.existing?.program ?? '');
  late final _plan = TextEditingController(text: '${widget.existing?.planPerDay ?? 0}');
  late final _days = TextEditingController(text: '${widget.existing?.workDays ?? 26}');
  late final _shift = TextEditingController(text: '${widget.existing?.shiftHrs ?? 8}');
  late final _start = TextEditingController(text: widget.existing?.startDate ?? '');
  late final _target = TextEditingController(text: widget.existing?.targetDate ?? '');
  late final _plantPin = TextEditingController(text: widget.existing?.plantPincode ?? '');
  late String _status = widget.existing?.status ?? 'Setup';

  @override
  void dispose() {
    for (final c in [_id, _name, _program, _plan, _days, _shift, _start, _target, _plantPin]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.existing == null ? 'New customer / project' : 'Edit ${widget.existing!.id}'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.existing == null)
                TextField(
                  controller: _id,
                  textCapitalization: TextCapitalization.characters,
                  style: mono(size: 13),
                  decoration: const InputDecoration(
                    labelText: 'Short code',
                    helperText: '2-12 letters or digits, e.g. AXN',
                  ),
                ),
              const SizedBox(height: 12),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Customer / plant name')),
              const SizedBox(height: 12),
              TextField(controller: _program, decoration: const InputDecoration(labelText: 'Model / programme')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _plan,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Plan per day',
                      helperText: 'vehicles/day',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _days,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Working days/month'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _shift,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Shift hours'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _start,
                    decoration: const InputDecoration(labelText: 'Start date', hintText: 'YYYY-MM-DD'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _target,
                    decoration: const InputDecoration(labelText: 'Target date', hintText: 'YYYY-MM-DD'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _plantPin,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Plant pincode',
                  // BRD 4.3 - this is the origin every vendor distance is
                  // measured from, so it is worth saying what it is for.
                  helperText: 'Where this plant is. Vendor distances are routed from here.',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                dropdownColor: Brand.surface2,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'Setup', child: Text('Setup')),
                  DropdownMenuItem(value: 'Live', child: Text('Live')),
                  DropdownMenuItem(value: 'Closed', child: Text('Closed')),
                ],
                onChanged: (v) => setState(() => _status = v ?? 'Setup'),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.of(context).pop({
              if (widget.existing == null) 'id': _id.text.trim().toUpperCase(),
              'name': _name.text.trim(),
              'program': _program.text.trim(),
              'status': _status,
              'planPerDay': int.tryParse(_plan.text) ?? 0,
              'workDays': int.tryParse(_days.text) ?? 26,
              'shiftHrs': double.tryParse(_shift.text) ?? 8,
              'startDate': _start.text.trim(),
              'targetDate': _target.text.trim(),
              'plantPincode': _plantPin.text.trim(),
            }),
            child: Text(widget.existing == null ? 'Create' : 'Save'),
          ),
        ],
      );
}
