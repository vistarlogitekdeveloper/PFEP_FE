import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../data/providers.dart';
import '../widgets/common.dart';

/// Create a single part and map it to one or more vendors (BRD 4.1).
///
/// Pops with the request body for `POST /customers/:cid/parts`, or null if
/// cancelled. Each selected vendor becomes its own PFEP record for this part -
/// the same grain the bulk upload produces, so a hand-added part is
/// indistinguishable from an uploaded one downstream.
class AddPartDialog extends ConsumerStatefulWidget {
  const AddPartDialog({super.key});

  @override
  ConsumerState<AddPartDialog> createState() => _AddPartDialogState();
}

class _AddPartDialogState extends ConsumerState<AddPartDialog> {
  final _partNo = TextEditingController();
  final _desc = TextEditingController();
  final _type = TextEditingController();
  final _model = TextEditingController();
  final _qty = TextEditingController(text: '1');
  final _price = TextEditingController();
  String? _abc;
  final Set<String> _vendors = {};
  String _vq = '';

  @override
  void dispose() {
    for (final c in [_partNo, _desc, _type, _model, _qty, _price]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit =>
      _partNo.text.trim().isNotEmpty && _desc.text.trim().isNotEmpty && _vendors.isNotEmpty;

  void _submit() {
    Navigator.pop(context, <String, dynamic>{
      'partNo': _partNo.text.trim().toUpperCase(),
      'description': _desc.text.trim(),
      if (_type.text.trim().isNotEmpty) 'partType': _type.text.trim(),
      if (_model.text.trim().isNotEmpty) 'model': _model.text.trim(),
      'qtyPerVehicle': num.tryParse(_qty.text.trim()) ?? 1,
      if (_price.text.trim().isNotEmpty) 'unitPrice': num.tryParse(_price.text.trim()),
      if (_abc != null) 'abcClass': _abc,
      'vendorIds': _vendors.toList(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final vendorsAsync = ref.watch(vendorsProvider);

    return AlertDialog(
      title: const Text('Add a part'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Creates the part and one PFEP record per vendor you map to it. Those records '
                'then appear for the assigned collector to fill.',
                style: body(size: 11.5, color: Brand.txt3, height: 1.45),
              ),
              const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextField(
                    controller: _partNo,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Part number *', hintText: '90210-ABX'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _qty,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Qty / vehicle'),
                  ),
                ),
              ]),
              const SizedBox(height: 12),
              TextField(
                controller: _desc,
                decoration: const InputDecoration(labelText: 'Description *'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: TextField(
                        controller: _type,
                        decoration: const InputDecoration(labelText: 'Part type'))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                        controller: _model,
                        decoration: const InputDecoration(labelText: 'Model / programme'))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Unit price'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _abc,
                    decoration: const InputDecoration(labelText: 'ABC class'),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('-')),
                      DropdownMenuItem(value: 'A', child: Text('A')),
                      DropdownMenuItem(value: 'B', child: Text('B')),
                      DropdownMenuItem(value: 'C', child: Text('C')),
                    ],
                    onChanged: (v) => setState(() => _abc = v),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              Row(children: [
                Text('VENDORS *', style: fieldLabel()),
                const Spacer(),
                Text('${_vendors.length} selected', style: body(size: 11, color: Brand.txt3)),
              ]),
              const SizedBox(height: 4),
              Text('Each vendor becomes its own record for this part.',
                  style: body(size: 11, color: Brand.txt3)),
              const SizedBox(height: 8),
              TextField(
                decoration: const InputDecoration(
                    hintText: 'Search vendors', prefixIcon: Icon(Icons.search, size: 18)),
                onChanged: (v) => setState(() => _vq = v.toLowerCase()),
              ),
              const SizedBox(height: 8),
              Container(
                height: 200,
                decoration: BoxDecoration(
                  border: Border.all(color: Brand.line),
                  borderRadius: BorderRadius.circular(10),
                ),
                clipBehavior: Clip.antiAlias,
                child: vendorsAsync.when(
                  loading: () => const Center(
                      child: SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                  error: (e, _) => Center(
                      child: Text('Could not load vendors: $e',
                          style: body(size: 12, color: Brand.bad), textAlign: TextAlign.center)),
                  data: (vendors) {
                    final filtered = vendors
                        .where((v) =>
                            _vq.isEmpty ||
                            v.name.toLowerCase().contains(_vq) ||
                            v.id.toLowerCase().contains(_vq))
                        .toList();
                    if (filtered.isEmpty) {
                      return const Center(
                          child: EmptyState(message: 'No vendor matches. Add it under Vendors first.'));
                    }
                    return ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        for (final v in filtered)
                          CheckboxListTile(
                            dense: true,
                            value: _vendors.contains(v.id),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (on) => setState(() {
                              if (on == true) {
                                _vendors.add(v.id);
                              } else {
                                _vendors.remove(v.id);
                              }
                            }),
                            title: Text(v.name, style: body(size: 13, weight: FontWeight.w600)),
                            subtitle: Text(
                              '${v.id}${v.city != null && v.city!.isNotEmpty ? '  -  ${v.city}' : ''}',
                              style: body(size: 11, color: Brand.txt3),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _canSubmit ? _submit : null, child: const Text('Add part')),
      ],
    );
  }
}
