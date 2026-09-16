import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../models/models.dart';

/// Renders one PFEP section straight from the customer field config.
///
/// BRD 4.3/4.4 are explicit that the field list changes per customer, so the
/// form is never hard-coded: whatever the admin enabled in Field Config is what
/// the field team sees here, in that order, with that required flag.
class DynamicForm extends StatefulWidget {
  const DynamicForm({
    super.key,
    required this.section,
    required this.values,
    required this.onChanged,
    this.enabled = true,
    this.highlightMissing = const {},
  });

  final FieldSection section;
  final Map<String, dynamic> values;
  final void Function(String key, dynamic value) onChanged;
  final bool enabled;
  final Set<String> highlightMissing;

  @override
  State<DynamicForm> createState() => _DynamicFormState();
}

class _DynamicFormState extends State<DynamicForm> {
  final _controllers = <String, TextEditingController>{};

  @override
  void didUpdateWidget(DynamicForm old) {
    super.didUpdateWidget(old);
    // Keep controllers in step when the record is reloaded from the server.
    for (final entry in _controllers.entries) {
      final incoming = '${widget.values[entry.key] ?? ''}';
      if (entry.value.text != incoming && !entry.value.selection.isValid) {
        entry.value.text = incoming;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(FieldDef f) => _controllers.putIfAbsent(
        f.key,
        () => TextEditingController(text: '${widget.values[f.key] ?? ''}'),
      );

  @override
  Widget build(BuildContext context) {
    final fields = widget.section.active;
    final wide = MediaQuery.sizeOf(context).width >= 720;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Dimensions read best side by side, so L/B/H triples are grouped.
      for (final group in _group(fields))
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: group.length == 1
              ? _field(group.first)
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < group.length; i++) ...[
                      if (i > 0) const SizedBox(width: 10),
                      Expanded(child: _field(group[i], dense: true)),
                    ],
                  ],
                ),
        ),
      if (fields.isEmpty)
        Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Text('Every field in this section is switched off for this customer.',
              textAlign: TextAlign.center, style: TextStyle(color: Brand.txt3, fontSize: 12.5)),
        ),
      if (!wide) const SizedBox(height: 4),
    ]);
  }

  /// Groups the L / B / H dimension triples onto one row.
  List<List<FieldDef>> _group(List<FieldDef> fields) {
    final out = <List<FieldDef>>[];
    var i = 0;
    while (i < fields.length) {
      final f = fields[i];
      final isDim = f.unit == 'mm' && f.label.trim().endsWith('L');
      if (isDim && i + 2 < fields.length && fields[i + 1].unit == 'mm' && fields[i + 2].unit == 'mm') {
        out.add([f, fields[i + 1], fields[i + 2]]);
        i += 3;
      } else {
        out.add([f]);
        i += 1;
      }
    }
    return out;
  }

  Widget _field(FieldDef f, {bool dense = false}) {
    final missing = widget.highlightMissing.contains(f.key);
    final label = Row(children: [
      Flexible(
        child: Text(
          dense ? f.label.split(' ').last : f.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: missing ? Brand.bad : Brand.txt2,
          ),
        ),
      ),
      if (f.required)
        Padding(
          padding: EdgeInsets.only(left: 3),
          child: Text('*', style: TextStyle(color: Brand.pink, fontSize: 13, fontWeight: FontWeight.w800)),
        ),
      if (f.unit != null && !dense) ...[
        const SizedBox(width: 6),
        Text(f.unit!, style: TextStyle(color: Brand.txt3, fontSize: 10.5)),
      ],
    ]);

    Widget input;
    switch (f.type) {
      case 'select':
        final options = f.options ?? const <String>[];
        final current = widget.values[f.key];
        input = DropdownButtonFormField<String>(
          initialValue: options.contains(current) ? '$current' : null,
          isExpanded: true,
          dropdownColor: Brand.surface2,
          hint: Text('Select', style: TextStyle(color: Brand.txt3, fontSize: 13)),
          decoration: InputDecoration(
            errorText: missing ? 'Required' : null,
            suffixText: dense ? f.unit : null,
          ),
          items: [
            for (final o in options)
              DropdownMenuItem(value: o, child: Text(o, style: TextStyle(fontSize: 13.5))),
          ],
          onChanged: widget.enabled ? (v) => widget.onChanged(f.key, v) : null,
        );
        break;

      case 'number':
        input = TextFormField(
          controller: _controllerFor(f),
          enabled: widget.enabled,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
          style: mono(size: 13.5),
          decoration: InputDecoration(
            hintText: '0',
            suffixText: dense ? f.unit : null,
            errorText: missing ? 'Required' : null,
          ),
          onChanged: (v) => widget.onChanged(f.key, v.isEmpty ? null : (num.tryParse(v) ?? v)),
        );
        break;

      case 'bool':
        final on = widget.values[f.key] == true || widget.values[f.key] == 'Yes';
        input = SwitchListTile(
          value: on,
          contentPadding: EdgeInsets.zero,
          dense: true,
          activeThumbColor: Brand.pink,
          title: Text(on ? 'Yes' : 'No', style: TextStyle(fontSize: 13)),
          onChanged: widget.enabled ? (v) => widget.onChanged(f.key, v ? 'Yes' : 'No') : null,
        );
        break;

      default:
        input = TextFormField(
          controller: _controllerFor(f),
          enabled: widget.enabled,
          style: TextStyle(fontSize: 13.5),
          decoration: InputDecoration(
            hintText: f.label,
            errorText: missing ? 'Required' : null,
          ),
          onChanged: (v) => widget.onChanged(f.key, v.isEmpty ? null : v),
        );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      label,
      const SizedBox(height: 6),
      input,
    ]);
  }
}

/// The computed strip shown under each section: values the app derives rather
/// than asking the field user to calculate (BRD 4.9).
class ComputedStrip extends StatelessWidget {
  const ComputedStrip({super.key, required this.computed, required this.keys, required this.catalogue});

  final Map<String, dynamic> computed;
  final List<String> keys;
  final List<ComputedFieldInfo> catalogue;

  @override
  Widget build(BuildContext context) {
    final entries = keys
        .map((k) => (k, catalogue.where((c) => c.key == k).firstOrNull))
        .where((e) => e.$2 != null && computed[e.$1] != null)
        .toList();
    if (entries.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
      decoration: BoxDecoration(
        color: Brand.violet.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Brand.violet.withValues(alpha: 0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.auto_awesome, size: 13, color: Brand.violet),
          const SizedBox(width: 7),
          Text('CALCULATED AUTOMATICALLY',
              style: TextStyle(
                  color: Brand.violet, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1.1)),
        ]),
        const SizedBox(height: 10),
        Wrap(
          spacing: 20,
          runSpacing: 10,
          children: [
            for (final (key, info) in entries)
              Tooltip(
                message: info!.formula,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(info.label,
                      style: TextStyle(color: Brand.txt3, fontSize: 10, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(_fmt(computed[key]),
                      style: mono(size: 14, weight: FontWeight.w800, color: Brand.txt)),
                ]),
              ),
          ],
        ),
      ]),
    );
  }

  String _fmt(dynamic v) {
    if (v == null) return '-';
    if (v is num) {
      if (v == v.roundToDouble()) return v.round().toString();
      return v.toStringAsFixed(2);
    }
    return '$v';
  }
}
