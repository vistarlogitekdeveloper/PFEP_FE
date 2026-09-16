import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

/// BRD 4.3 / 4.4 - the field list is an example, not a fixed schema.
///
/// Each customer PFEP format differs, so the admin turns fields on or off and
/// adds new ones here. The mobile form, the validation and the Excel export all
/// read this configuration, so nothing has to be rebuilt per client.
class FieldConfigScreen extends ConsumerStatefulWidget {
  const FieldConfigScreen({super.key});

  @override
  ConsumerState<FieldConfigScreen> createState() => _FieldConfigScreenState();
}

class _FieldConfigScreenState extends ConsumerState<FieldConfigScreen> {
  bool _busy = false;

  Future<void> _toggle(String section, FieldDef f, {bool? enabled, bool? required}) async {
    final cid = ref.read(activeCustomerIdProvider);
    if (cid == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).toggleField(cid, section, f.key, enabled: enabled, required: required);
      ref.invalidate(fieldConfigProvider);
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Could not update the field', detail: e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addField(FieldSection section) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _AddFieldDialog(section: section),
    );
    if (result == null) return;
    final cid = ref.read(activeCustomerIdProvider);
    if (cid == null) return;
    try {
      await ref.read(repositoryProvider).addField(cid, section.key, result);
      ref.invalidate(fieldConfigProvider);
      if (mounted) {
        showToast(context, 'Field added',
            detail: '"${result['label']}" now appears in the ${section.label} section on the phone.');
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Could not add the field', detail: e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(fieldConfigProvider);
    final customer = ref.watch(sessionProvider).activeCustomer;

    return ListView(
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 40),
      children: [
        config.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
          data: (c) {
            final defined = c?.sections.fold<int>(0, (s, x) => s + x.fields.length) ?? 0;
            final enabled = c?.sections.fold<int>(0, (s, x) => s + x.active.length) ?? 0;
            return PageHeader(
              crumb: 'Setup ·',
              accent: 'Field Config',
              title: 'Configurable field sets',
              blurb: 'Field lists are examples, not fixed - each customer PFEP format differs. '
                  'Toggle fields per section for ${customer?.name ?? 'this customer'}; '
                  'the field app renders only what is enabled.',
              blurbHighlight: customer?.name,
              actions: [
                if (_busy)
                  Pill('Saving', tone: PillTone.info, icon: Icons.sync)
                else
                  Pill('$enabled of $defined fields enabled', tone: PillTone.pink, dot: true),
              ],
            );
          },
        ),
        config.when(
          loading: () => const Loading(label: 'Loading field configuration...'),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(fieldConfigProvider)),
          data: (c) {
            if (c == null) return const EmptyState(message: 'No customer selected.');
            final twoUp = MediaQuery.sizeOf(context).width >= 1040;

            final cards = [
              for (final section in c.sections)
                _SectionCard(
                  section: section,
                  onToggle: (f, enabled) => _toggle(section.key, f, enabled: enabled),
                  onRequired: (f, req) => _toggle(section.key, f, required: req),
                  onAdd: () => _addField(section),
                ),
            ];

            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (twoUp)
                for (var i = 0; i < cards.length; i += 2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: cards[i]),
                        const SizedBox(width: 16),
                        Expanded(child: i + 1 < cards.length ? cards[i + 1] : const SizedBox.shrink()),
                      ]),
                    ),
                  )
              else
                for (final card in cards) Padding(padding: const EdgeInsets.only(bottom: 16), child: card),
              AlertBox(
                tone: AlertTone.info,
                title: 'No hard-coding',
                message: 'Adding a customer never needs a rebuild - an admin enables or disables fields here '
                    'and the collector form, the validations, the Excel columns and the labels follow '
                    'automatically.',
              ),
              const SizedBox(height: 16),
              _ComputedCard(fields: c.computedFields),
            ]);
          },
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.section,
    required this.onToggle,
    required this.onRequired,
    required this.onAdd,
  });

  final FieldSection section;
  final void Function(FieldDef, bool enabled) onToggle;
  final void Function(FieldDef, bool required) onRequired;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => PfepCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle(
            section.label,
            trailingWidget: Row(mainAxisSize: MainAxisSize.min, children: [
              Text('${section.active.length}/${section.fields.length} on',
                  style: body(size: 12.5, weight: FontWeight.w600, color: Brand.txt3)),
              const SizedBox(width: 8),
              InkWell(
                onTap: onAdd,
                borderRadius: BorderRadius.circular(8),
                child: Tooltip(
                  message: 'Add a field to ${section.label}',
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(Icons.add, size: 16, color: Brand.pink),
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 13),
          for (final f in section.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FieldRow(
                field: f,
                onToggle: () => onToggle(f, !f.enabled),
                onRequired: () => onRequired(f, !f.required),
              ),
            ),
        ]),
      );
}

/// `.listrow` with the field name, its type, whether it is mandatory, and a
/// single Enable/Disable action - the prototype's row, kept intact.
class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.field, required this.onToggle, required this.onRequired});

  final FieldDef field;
  final VoidCallback onToggle;
  final VoidCallback onRequired;

  /// The pills and the Enable/Disable button need roughly 200px between them.
  /// Under this width that left the field name about forty, and a label like
  /// "Vendor Location / City" broke mid-word into "Vendo r Loca". Below it the
  /// name gets the full width and the controls sit underneath.
  static const _stackBelow = 380.0;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      field.labelWithUnit,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: body(
        size: 13,
        weight: FontWeight.w700,
        color: field.enabled ? Brand.txt : Brand.txt3,
        decoration: field.enabled ? null : TextDecoration.lineThrough,
      ),
    );

    final typePill = Pill(field.type, tone: PillTone.neutral, size: 10);

    final requiredPill = field.required
        ? InkWell(
            onTap: field.enabled ? onRequired : null,
            borderRadius: BorderRadius.circular(20),
            child: Pill('mandatory', tone: PillTone.pink, dot: true, size: 10),
          )
        : field.enabled
            ? Tooltip(
                message: 'Make mandatory',
                child: InkWell(
                  onTap: onRequired,
                  borderRadius: BorderRadius.circular(20),
                  child: Pill('optional', tone: PillTone.neutral, size: 10),
                ),
              )
            : null;

    final action = GhostButton(
      label: field.enabled ? 'Disable' : 'Enable',
      small: true,
      onPressed: onToggle,
    );

    return ListRow(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: LayoutBuilder(
        builder: (context, box) {
          if (box.maxWidth < _stackBelow) {
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              label,
              const SizedBox(height: 9),
              Row(children: [
                typePill,
                if (requiredPill != null) ...[const SizedBox(width: 6), requiredPill],
                const Spacer(),
                action,
              ]),
            ]);
          }
          return Row(children: [
            Expanded(child: label),
            const SizedBox(width: 8),
            typePill,
            if (requiredPill != null) ...[const SizedBox(width: 6), requiredPill],
            const SizedBox(width: 10),
            action,
          ]);
        },
      ),
    );
  }
}

class _ComputedCard extends StatelessWidget {
  const _ComputedCard({required this.fields});

  final List<ComputedFieldInfo> fields;

  @override
  Widget build(BuildContext context) => Panel(
        title: 'Calculated automatically',
        trailingText: '${fields.length} values',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'These are never typed by the field team - the app derives each one from data already captured '
            'plus the production plan, which removes both the effort and the arithmetic errors (BRD 4.9).',
            style: body(size: 12.5, color: Brand.txt3, height: 1.55),
          ),
          const SizedBox(height: 16),
          for (final f in fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  width: 250,
                  child: Text(f.label, style: body(size: 12.3, weight: FontWeight.w700)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(f.formula, style: body(size: 11.8, color: Brand.txt3, height: 1.45)),
                ),
              ]),
            ),
        ]),
      );
}

class _AddFieldDialog extends StatefulWidget {
  const _AddFieldDialog({required this.section});

  final FieldSection section;

  @override
  State<_AddFieldDialog> createState() => _AddFieldDialogState();
}

class _AddFieldDialogState extends State<_AddFieldDialog> {
  final _key = TextEditingController();
  final _label = TextEditingController();
  final _unit = TextEditingController();
  final _options = TextEditingController();
  String _type = 'text';
  bool _required = false;

  /// Fills the form from one of the wider-PFEP presets, so the key, type, unit
  /// and dropdown values are the standard ones rather than retyped guesses.
  void _usePreset(FieldDef preset) {
    setState(() {
      _key.text = preset.key;
      _label.text = preset.label;
      _type = preset.type;
      _unit.text = preset.unit ?? '';
      _options.text = (preset.options ?? const []).join(', ');
    });
  }

  @override
  void dispose() {
    _key.dispose();
    _label.dispose();
    _unit.dispose();
    _options.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Add a field to ${widget.section.label}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (widget.section.availableExtras.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('FROM THE WIDER PFEP MASTER', style: fieldLabel()),
                ),
                const SizedBox(height: 7),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'These are not in the standard 43. Pick one to fill the form with its '
                    'usual key, type and choices.',
                    style: body(size: 11.5, color: Brand.txt3, height: 1.45),
                  ),
                ),
                const SizedBox(height: 9),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in widget.section.availableExtras)
                      SelectChip(
                        label: p.labelWithUnit,
                        selected: _key.text == p.key,
                        onTap: () => _usePreset(p),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Divider(color: Brand.line, height: 1),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Label shown on the phone'),
                onChanged: (v) {
                  if (_key.text.isEmpty || _key.text == _slug(_label.text)) _key.text = _slug(v);
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _key,
                style: mono(size: 13),
                decoration: const InputDecoration(
                  labelText: 'Field key',
                  helperText: 'Used as the column key in the Excel export',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'text', child: Text('Text')),
                  DropdownMenuItem(value: 'number', child: Text('Number')),
                  DropdownMenuItem(value: 'select', child: Text('Dropdown')),
                  DropdownMenuItem(value: 'bool', child: Text('Yes / No')),
                  DropdownMenuItem(value: 'date', child: Text('Date')),
                ],
                onChanged: (v) => setState(() => _type = v ?? 'text'),
              ),
              const SizedBox(height: 12),
              if (_type == 'number')
                TextField(
                  controller: _unit,
                  decoration: const InputDecoration(labelText: 'Unit (mm, kg, nos...)'),
                ),
              if (_type == 'select')
                TextField(
                  controller: _options,
                  decoration: const InputDecoration(labelText: 'Options', helperText: 'Comma separated'),
                ),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: _required,
                onChanged: (v) => setState(() => _required = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: Text('Mandatory - block submission if blank', style: body(size: 12.5)),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('Cancel')),
          FilledButton(
            onPressed: _label.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop({
                      'key': _key.text.trim(),
                      'label': _label.text.trim(),
                      'type': _type,
                      'required': _required,
                      if (_unit.text.trim().isNotEmpty) 'unit': _unit.text.trim(),
                      if (_type == 'select')
                        'options':
                            _options.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
                    }),
            child: Text('Add field'),
          ),
        ],
      );

  String _slug(String s) {
    final words = s.trim().split(RegExp(r'[^A-Za-z0-9]+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '';
    return words.first.toLowerCase() +
        words.skip(1).map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase()).join();
  }
}
