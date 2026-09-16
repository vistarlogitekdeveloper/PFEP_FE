import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// Vendor master. Distance and transport mode live here because they drive the
/// derived lead time, and therefore the reorder point and safety stock, for
/// every part that vendor supplies.
class VendorsScreen extends ConsumerWidget {
  const VendorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendors = ref.watch(vendorsProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
      children: [
        PageHeader(
          crumb: 'Setup ·',
          accent: 'Vendors',
          title: 'Vendor master',
          blurb: 'Shared across customers, because the same supplier often feeds more than one plant. '
              'Distance and transport mode captured here become the default lead time used by the '
              'reorder point and safety stock calculations.',
          actions: [
            FilledButton.icon(
              onPressed: () => _edit(context, ref, null),
              icon: Icon(Icons.add, size: 17),
              label: Text('Add vendor'),
            ),
          ],
        ),
        vendors.when(
          loading: () => const Loading(),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(vendorsProvider)),
          data: (list) => ScrollTable(
            emptyMessage: 'No vendors yet. They are also created automatically by a part master upload.',
            columns: const [
              DataColumn(label: Text('CODE')),
              DataColumn(label: Text('VENDOR')),
              DataColumn(label: Text('LOCATION')),
              DataColumn(label: Text('COUNTRY')),
              DataColumn(label: Text('DISTANCE')),
              DataColumn(label: Text('MODE')),
              DataColumn(label: Text('VEHICLE')),
              DataColumn(label: Text('PARTS')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final v in list)
                DataRow(cells: [
                  DataCell(Text(v.id, style: mono(size: 11.5, color: Brand.pink))),
                  DataCell(Text(v.name, style: TextStyle(fontWeight: FontWeight.w600))),
                  DataCell(Text(v.city ?? '-')),
                  DataCell(Text(v.country ?? '-')),
                  // A routed estimate and a surveyed figure drive the same
                  // reorder point, so the measured ones are marked rather than
                  // sitting in the column looking equally authoritative.
                  DataCell(Tooltip(
                    message: v.distanceSource ?? 'No source recorded',
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(v.distanceKm == null ? '-' : '${fmtNum(v.distanceKm)} km',
                          style: mono(size: 11.5)),
                      if (v.distanceIsMeasured) ...[
                        const SizedBox(width: 5),
                        Icon(Icons.route_outlined, size: 12, color: Brand.txt3),
                      ],
                    ]),
                  )),
                  DataCell(Text(v.transportMode ?? '-')),
                  DataCell(Text(v.vehicleType ?? '-')),
                  DataCell(Text('${v.partCount}', style: mono(size: 11.5, color: Brand.txt2))),
                  DataCell(IconButton(
                    icon: Icon(Icons.edit_outlined, size: 15),
                    onPressed: () => _edit(context, ref, v),
                  )),
                ]),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Vendor? existing) async {
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _VendorDialog(existing: existing),
    );
    if (body == null) return;
    try {
      final repo = ref.read(repositoryProvider);
      if (existing == null) {
        await repo.createVendor(body);
      } else {
        await repo.updateVendor(existing.id, body);
      }
      ref.invalidate(vendorsProvider);
      if (context.mounted) showToast(context, existing == null ? 'Vendor added' : 'Vendor updated');
    } on ApiException catch (e) {
      if (context.mounted) showToast(context, 'Could not save', detail: e.message, error: true);
    }
  }
}

class _VendorDialog extends ConsumerStatefulWidget {
  const _VendorDialog({this.existing});

  final Vendor? existing;

  @override
  ConsumerState<_VendorDialog> createState() => _VendorDialogState();
}

class _VendorDialogState extends ConsumerState<_VendorDialog> {
  late final _id = TextEditingController(text: widget.existing?.id ?? '');
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _city = TextEditingController(text: widget.existing?.city ?? '');
  late final _country = TextEditingController(text: widget.existing?.country ?? 'India');
  late final _pincode = TextEditingController(text: widget.existing?.pincode ?? '');
  late final _km = TextEditingController(
      text: widget.existing?.distanceKm == null ? '' : '${widget.existing!.distanceKm}');
  late String _mode = widget.existing?.transportMode ?? 'Road';
  late String _vehicle = widget.existing?.vehicleType ?? 'LCV';

  /// Where the distance currently on screen came from, so the admin can see
  /// whether they are looking at a surveyed figure or a routed estimate.
  late String? _source = widget.existing?.distanceSource;
  bool _measuring = false;

  static const _modes = ['Road', 'Rail', 'Air', 'Sea', 'Multimodal', 'Milk Run', 'Direct'];
  static const _vehicles = ['LCV', '14 ft Truck', '20 ft Truck', '32 ft Truck', 'Trailer'];

  @override
  void dispose() {
    for (final c in [_id, _name, _city, _country, _km, _pincode]) {
      c.dispose();
    }
    super.dispose();
  }

  /// BRD 4.3 - route from the customer's plant to this vendor's pincode.
  ///
  /// This writes straight away and is audited, rather than waiting for Save:
  /// it can overwrite a surveyed distance that feeds every reorder point, so it
  /// is its own deliberate action with its own trail. The button says so.
  Future<void> _measure() async {
    final cid = ref.read(activeCustomerIdProvider);
    if (cid == null || widget.existing == null) return;

    setState(() => _measuring = true);
    // Held before the call so the toast can say what the number replaced - the
    // difference between a surveyed figure and a routed one is the thing worth
    // noticing, and it is gone from the field the moment this returns.
    final was = double.tryParse(_km.text);

    try {
      final v = await ref.read(repositoryProvider).measureVendorDistance(widget.existing!.id, cid);
      if (!mounted) return;
      setState(() {
        _km.text = v.distanceKm == null ? '' : '${v.distanceKm}';
        _source = v.distanceSource;
      });
      ref.invalidate(vendorsProvider);
      showToast(
        context,
        'Measured ${v.distanceKm} km',
        // The source already names both endpoints, so it is not repeated here.
        detail: '${v.distanceSource ?? ''}'
            '${was == null ? '' : '. Replaces the previous ${fmtNum(was)} km'}',
      );
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Could not measure the distance', detail: e.message, error: true);
    } finally {
      if (mounted) setState(() => _measuring = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.existing == null ? 'Add vendor' : 'Edit ${widget.existing!.id}'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.existing == null)
                TextField(
                  controller: _id,
                  textCapitalization: TextCapitalization.characters,
                  style: mono(size: 13),
                  decoration: const InputDecoration(labelText: 'Vendor code', hintText: 'V-1042'),
                ),
              const SizedBox(height: 12),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Vendor name')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  flex: 2,
                  child: TextField(controller: _city, decoration: const InputDecoration(labelText: 'Location / city')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _pincode,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Pincode'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: TextField(controller: _country, decoration: const InputDecoration(labelText: 'Country'))),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _km,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Distance from plant', suffixText: 'km'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _mode,
                    dropdownColor: Brand.surface2,
                    decoration: const InputDecoration(labelText: 'Transport mode'),
                    items: [for (final m in _modes) DropdownMenuItem(value: m, child: Text(m))],
                    onChanged: (v) => setState(() => _mode = v ?? 'Road'),
                  ),
                ),
              ]),
              _DistanceHelp(
                existing: widget.existing,
                pincode: _pincode.text,
                source: _source,
                measuring: _measuring,
                onMeasure: _measure,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _vehicle,
                dropdownColor: Brand.surface2,
                decoration: const InputDecoration(labelText: 'Vehicle type'),
                items: [for (final v in _vehicles) DropdownMenuItem(value: v, child: Text(v))],
                onChanged: (v) => setState(() => _vehicle = v ?? 'LCV'),
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
              'city': _city.text.trim(),
              'country': _country.text.trim(),
              'pincode': _pincode.text.trim(),
              'distanceKm': double.tryParse(_km.text),
              'transportMode': _mode,
              'vehicleType': _vehicle,
            }),
            child: Text(widget.existing == null ? 'Add' : 'Save'),
          ),
        ],
      );
}

/// BRD 4.3 — the optional "auto-calculated once vendor address/pincode is
/// captured, via map API" half of the distance field.
///
/// It says which of four states it is in rather than just hiding the button:
/// an admin who expects to measure and finds nothing needs to know whether it
/// is a server setting, a missing plant, or a missing pincode.
class _DistanceHelp extends ConsumerWidget {
  const _DistanceHelp({
    required this.existing,
    required this.pincode,
    required this.source,
    required this.measuring,
    required this.onMeasure,
  });

  final Vendor? existing;
  final String pincode;
  final String? source;
  final bool measuring;
  final VoidCallback onMeasure;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(distanceStatusProvider).maybeWhen(
          data: (s) => s,
          orElse: () => null,
        );
    final customer = ref.watch(sessionProvider).activeCustomer;

    final note = switch (null) {
      _ when existing == null => 'Save the vendor first, then it can be measured from the plant.',
      _ when status == null => null,
      _ when !status.enabled => status.reason,
      _ when (customer?.plantPincode ?? '').isEmpty =>
        'Set the plant pincode on ${customer?.name ?? 'this customer'} to measure distances from it.',
      _ when pincode.trim().isEmpty => 'Add this vendor\'s pincode to measure the distance.',
      _ => null,
    };
    final canMeasure = note == null && !measuring && status != null && status.enabled;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (canMeasure || measuring)
          GhostButton(
            label: measuring ? 'Measuring...' : 'Measure & save from plant',
            icon: Icons.route_outlined,
            small: true,
            onPressed: measuring ? null : onMeasure,
          ),
        if (note != null)
          Text(note, style: body(size: 11, color: Brand.txt3, height: 1.4)),
        if (source != null && source!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Current figure: $source',
              style: body(size: 10.8, color: Brand.txt3, height: 1.4)),
        ],
        if (canMeasure) ...[
          const SizedBox(height: 4),
          Text('Routes from the plant now and saves the result — it replaces the distance above.',
              style: body(size: 10.5, color: Brand.txt3, height: 1.4)),
        ],
      ]),
    );
  }
}
