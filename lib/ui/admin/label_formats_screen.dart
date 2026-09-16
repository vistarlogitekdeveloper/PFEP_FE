import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../data/providers.dart';
import '../../models/models.dart';
import '../widgets/common.dart';
import '../widgets/label_preview.dart';

/// BRD 4.8 - "Label size and layout to be configurable per customer, since each
/// customer has its own required label size, format and printer type."
///
/// The data model and API always supported that; this screen is what makes it
/// reachable without calling the API by hand. Everything on it maps to one
/// column of `label_templates`, and the preview resolves the same tokens the
/// renderer does, against a real record, so what an admin sees here is what
/// comes off the printer.
class LabelFormatsScreen extends ConsumerStatefulWidget {
  const LabelFormatsScreen({super.key});

  @override
  ConsumerState<LabelFormatsScreen> createState() => _LabelFormatsScreenState();
}

/// Substitutes `{token}` the way `services/labels.js` does, including its "-"
/// for anything missing, so the preview cannot flatter the real output.
String resolveTokens(String text, Map<String, LabelToken> index) =>
    text.replaceAllMapped(RegExp(r'\{(\w+)\}'), (m) {
      final v = index[m.group(1)]?.example;
      return v == null || v.isEmpty ? '-' : v;
    });

class _LabelFormatsScreenState extends ConsumerState<LabelFormatsScreen> {
  String _kind = 'rack';
  LabelTemplate? _draft;
  bool _busy = false;

  /// Bumped whenever the draft is replaced wholesale (kind switch, reset, save)
  /// so the plain text fields rebuild from the new values. Keying them on this
  /// rather than on their content means typing does not rebuild the field.
  int _rev = 0;

  LabelTemplate? _saved(LabelTemplateConfig c) {
    for (final t in c.templates) {
      if (t.kind == _kind) return t;
    }
    return null;
  }

  LabelTemplate? _current(LabelTemplateConfig c) => _draft ?? _saved(c);

  bool _dirty(LabelTemplateConfig c) {
    final saved = _saved(c);
    return _draft != null && saved != null && !_draft!.sameAs(saved);
  }

  void _set(LabelTemplate next) => setState(() => _draft = next);

  void _switchKind(String kind, LabelTemplateConfig c) {
    if (kind == _kind) return;
    if (_dirty(c)) {
      showToast(context, 'Unsaved changes',
          detail: 'Save or discard the ${_kindName(_kind)} format before switching.', error: true);
      return;
    }
    setState(() {
      _kind = kind;
      _draft = null;
      _rev++;
    });
  }

  static String _kindName(String k) => k == 'rack' ? 'warehouse rack' : 'line-side bin';

  String? _validate(LabelTemplate t) {
    if (t.name.trim().isEmpty) return 'Give the format a name.';
    if (t.widthMm < 10 || t.widthMm > 300) return 'Width must be between 10 and 300 mm.';
    if (t.heightMm < 10 || t.heightMm > 300) return 'Height must be between 10 and 300 mm.';
    if (t.lines.isEmpty) return 'A label needs at least one line.';
    if (t.lines.any((l) => l.token.trim().isEmpty)) return 'Every line needs some content.';
    return null;
  }

  Future<void> _save(LabelTemplateConfig c) async {
    final t = _current(c);
    if (t == null) return;
    final problem = _validate(t);
    if (problem != null) {
      showToast(context, 'Cannot save this format', detail: problem, error: true);
      return;
    }
    final cid = ref.read(activeCustomerIdProvider);
    if (cid == null) return;

    setState(() => _busy = true);
    try {
      await ref.read(repositoryProvider).saveLabelTemplate(cid, t);
      ref.invalidate(labelTemplatesProvider);
      if (mounted) {
        setState(() {
          _draft = null;
          _rev++;
        });
        showToast(context, 'Label format saved',
            detail: '${t.name} - ${_mm(t.widthMm)} x ${_mm(t.heightMm)} mm. '
                'Every label printed for this customer uses it from now on.');
      }
    } on ApiException catch (e) {
      if (mounted) showToast(context, 'Could not save the format', detail: e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _mm(double v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

  Future<void> _editLine(LabelTemplate t, int? index, LabelTemplateConfig c) async {
    final line = await showDialog<LabelTemplateLine>(
      context: context,
      builder: (_) => _LineDialog(
        line: index == null ? null : t.lines[index],
        config: c,
        sizes: c.sizes,
      ),
    );
    if (line == null) return;
    final lines = [...t.lines];
    if (index == null) {
      lines.add(line);
    } else {
      lines[index] = line;
    }
    _set(t.copyWith(lines: lines));
  }

  void _moveLine(LabelTemplate t, int from, int to) {
    if (to < 0 || to >= t.lines.length) return;
    final lines = [...t.lines];
    final item = lines.removeAt(from);
    lines.insert(to, item);
    _set(t.copyWith(lines: lines));
  }

  void _removeLine(LabelTemplate t, int index) {
    final lines = [...t.lines]..removeAt(index);
    _set(t.copyWith(lines: lines));
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(labelTemplatesProvider);
    final customer = ref.watch(sessionProvider).activeCustomer;

    return ListView(
      padding: const EdgeInsets.fromLTRB(26, 26, 26, 40),
      children: [
        PageHeader(
          crumb: 'Setup ·',
          accent: 'Label Formats',
          title: 'Warehouse & line-side label formats',
          blurb: 'Each plant has its own label stock and printer, so size, layout and content '
              'are set per customer rather than in code. What you build here is exactly what '
              '${customer?.name ?? 'this customer'} prints - single labels, bulk runs, PDF and ZPL alike.',
          blurbHighlight: customer?.name,
          actions: [
            if (_busy)
              Pill('Saving', tone: PillTone.info, icon: Icons.sync)
            else
              config.maybeWhen(
                data: (c) => c != null && _dirty(c)
                    ? Pill('Unsaved changes', tone: PillTone.amber, dot: true)
                    : Pill('Saved', tone: PillTone.ok, icon: Icons.check),
                orElse: () => const SizedBox.shrink(),
              ),
          ],
        ),
        config.when(
          loading: () => const Loading(label: 'Loading label formats...'),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(labelTemplatesProvider)),
          data: (c) {
            if (c == null) return const EmptyState(message: 'No customer selected.');
            final t = _current(c);
            if (t == null) {
              return const EmptyState(message: 'This customer has no label formats yet.');
            }
            final index = c.tokenIndex;
            final wide = MediaQuery.sizeOf(context).width >= 1060;

            final form = _FormColumn(
              key: ValueKey('form-$_kind-$_rev'),
              template: t,
              config: c,
              rev: _rev,
              onChanged: _set,
              onEditLine: (i) => _editLine(t, i, c),
              onAddLine: () => _editLine(t, null, c),
              onMove: (from, to) => _moveLine(t, from, to),
              onRemove: (i) => _removeLine(t, i),
              index: index,
            );

            final preview = _PreviewColumn(
              template: t,
              index: index,
              samplePartNo: c.samplePartNo,
            );

            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _KindBar(
                kind: _kind,
                templates: c.templates,
                onChanged: (k) => _switchKind(k, c),
              ),
              const SizedBox(height: 16),
              if (wide)
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(flex: 3, child: form),
                  const SizedBox(width: 18),
                  Expanded(flex: 2, child: preview),
                ])
              else ...[
                preview,
                const SizedBox(height: 16),
                form,
              ],
              const SizedBox(height: 18),
              _SaveBar(
                busy: _busy,
                dirty: _dirty(c),
                onSave: () => _save(c),
                onReset: () => setState(() {
                  _draft = null;
                  _rev++;
                }),
              ),
            ]);
          },
        ),
      ],
    );
  }
}

/* ------------------------------------------------------------------- bits */

class _KindBar extends StatelessWidget {
  const _KindBar({required this.kind, required this.templates, required this.onChanged});

  final String kind;
  final List<LabelTemplate> templates;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final t in templates)
            SelectChip(
              label: '${t.name}   ${_LabelFormatsScreenState._mm(t.widthMm)} x '
                  '${_LabelFormatsScreenState._mm(t.heightMm)} mm',
              selected: t.kind == kind,
              onTap: () => onChanged(t.kind),
            ),
        ],
      );
}

class _FormColumn extends StatelessWidget {
  const _FormColumn({
    super.key,
    required this.template,
    required this.config,
    required this.rev,
    required this.onChanged,
    required this.onEditLine,
    required this.onAddLine,
    required this.onMove,
    required this.onRemove,
    required this.index,
  });

  final LabelTemplate template;
  final LabelTemplateConfig config;
  final int rev;
  final ValueChanged<LabelTemplate> onChanged;
  final ValueChanged<int> onEditLine;
  final VoidCallback onAddLine;
  final void Function(int from, int to) onMove;
  final ValueChanged<int> onRemove;
  final Map<String, LabelToken> index;

  @override
  Widget build(BuildContext context) {
    final t = template;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Panel(
        title: 'Stock & printer',
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _Field(
            label: 'Format name',
            child: TextFormField(
              key: ValueKey('name-$rev-${t.kind}'),
              initialValue: t.name,
              decoration: const InputDecoration(hintText: 'e.g. Warehouse rack label'),
              onChanged: (v) => onChanged(t.copyWith(name: v)),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, box) {
            final stack = box.maxWidth < 420;
            final w = _Field(
              label: 'Width',
              suffix: 'mm',
              child: TextFormField(
                key: ValueKey('w-$rev-${t.kind}'),
                initialValue: _LabelFormatsScreenState._mm(t.widthMm),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                onChanged: (v) => onChanged(t.copyWith(widthMm: double.tryParse(v) ?? 0)),
              ),
            );
            final h = _Field(
              label: 'Height',
              suffix: 'mm',
              child: TextFormField(
                key: ValueKey('h-$rev-${t.kind}'),
                initialValue: _LabelFormatsScreenState._mm(t.heightMm),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                onChanged: (v) => onChanged(t.copyWith(heightMm: double.tryParse(v) ?? 0)),
              ),
            );
            if (stack) {
              return Column(children: [w, const SizedBox(height: 12), h]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: w),
              const SizedBox(width: 12),
              Expanded(child: h),
            ]);
          }),
          const SizedBox(height: 12),
          _Field(
            label: 'Printer resolution',
            hint: 'Used to size the ZPL sent to a thermal printer. PDF output is unaffected.',
            child: DropdownButtonFormField<int>(
              initialValue: t.dpmm,
              items: const [
                DropdownMenuItem(value: 6, child: Text('6 dots/mm  -  152 dpi')),
                DropdownMenuItem(value: 8, child: Text('8 dots/mm  -  203 dpi')),
                DropdownMenuItem(value: 12, child: Text('12 dots/mm  -  300 dpi')),
                DropdownMenuItem(value: 24, child: Text('24 dots/mm  -  600 dpi')),
              ],
              onChanged: (v) => v == null ? null : onChanged(t.copyWith(dpmm: v)),
            ),
          ),
          const SizedBox(height: 14),
          _Toggle(
            title: 'Barcode across the foot',
            // Honest about what the renderers do: both emit Code 128, so this
            // is on/off rather than a choice of symbology.
            subtitle: 'Code 128 of the part number, on both the PDF and the ZPL.',
            value: t.hasBarcode,
            onChanged: (v) => onChanged(t.copyWith(barcode: v ? 'code128' : 'none')),
          ),
          _Toggle(
            title: 'QR code',
            subtitle: 'Encodes part, vendor, bin, line and station - enough to identify the bin '
                'without a lookup.',
            value: t.qr,
            onChanged: (v) => onChanged(t.copyWith(qr: v)),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Panel(
        title: 'Lines',
        trailing: GhostButton(label: 'Add line', small: true, onPressed: onAddLine),
        child: t.lines.isEmpty
            ? const EmptyState(message: 'No lines yet. Add one to start the layout.')
            : Column(children: [
                for (var i = 0; i < t.lines.length; i++)
                  _LineRow(
                    line: t.lines[i],
                    resolved: resolveTokens(t.lines[i].token, index),
                    first: i == 0,
                    last: i == t.lines.length - 1,
                    onTap: () => onEditLine(i),
                    onUp: () => onMove(i, i - 1),
                    onDown: () => onMove(i, i + 1),
                    onRemove: () => onRemove(i),
                  ),
              ]),
      ),
    ]);
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.suffix, this.hint});

  final String label;
  final Widget child;
  final String? suffix;
  final String? hint;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(label, style: fieldLabel()),
            if (suffix != null) ...[
              const SizedBox(width: 6),
              Text(suffix!, style: body(size: 11, color: Brand.txt3)),
            ],
          ]),
          const SizedBox(height: 6),
          child,
          if (hint != null) ...[
            const SizedBox(height: 5),
            Text(hint!, style: body(size: 11, color: Brand.txt3, height: 1.4)),
          ],
        ],
      );
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: body(size: 13, weight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(subtitle, style: body(size: 11.2, color: Brand.txt3, height: 1.4)),
            ]),
          ),
          const SizedBox(width: 12),
          Switch(value: value, onChanged: onChanged),
        ]),
      );
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.line,
    required this.resolved,
    required this.first,
    required this.last,
    required this.onTap,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });

  final LabelTemplateLine line;
  final String resolved;
  final bool first, last;
  final VoidCallback onTap, onUp, onDown, onRemove;

  @override
  Widget build(BuildContext context) => ListRow(
        padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
        child: Row(children: [
          Column(mainAxisSize: MainAxisSize.min, children: [
            _Arrow(icon: Icons.keyboard_arrow_up, onPressed: first ? null : onUp),
            _Arrow(icon: Icons.keyboard_arrow_down, onPressed: last ? null : onDown),
          ]),
          const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (line.label != null && line.label!.isNotEmpty)
                    Text(line.label!.toUpperCase(), style: eyebrow(size: 9.5, color: Brand.txt3)),
                  Text(resolved,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: body(size: 13, weight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(line.token,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(size: 10.8, color: Brand.pink)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Pill(line.size, tone: PillTone.neutral, size: 10),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: Brand.txt3),
            tooltip: 'Remove line',
            onPressed: onRemove,
          ),
        ]),
      );
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 26,
        height: 20,
        child: IconButton(
          padding: EdgeInsets.zero,
          iconSize: 17,
          icon: Icon(icon, color: onPressed == null ? Brand.line2 : Brand.txt2),
          onPressed: onPressed,
        ),
      );
}

class _PreviewColumn extends StatelessWidget {
  const _PreviewColumn({required this.template, required this.index, required this.samplePartNo});

  final LabelTemplate template;
  final Map<String, LabelToken> index;
  final String? samplePartNo;

  @override
  Widget build(BuildContext context) {
    final t = template;
    return Panel(
      title: 'Preview',
      trailingText: '${_LabelFormatsScreenState._mm(t.widthMm)} x '
          '${_LabelFormatsScreenState._mm(t.heightMm)} mm',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(
          samplePartNo == null
              ? 'No record captured yet, so the tokens below show as dashes.'
              : 'Drawn at the real aspect ratio, with values from $samplePartNo.',
          style: body(size: 11.3, color: Brand.txt3, height: 1.45),
        ),
        const SizedBox(height: 12),
        LabelFace(
          widthMm: t.widthMm,
          heightMm: t.heightMm,
          hasQr: t.qr,
          hasBarcode: t.hasBarcode,
          lines: [
            for (final l in t.lines)
              LabelFaceLine(
                label: l.label,
                value: resolveTokens(l.token, index),
                size: l.size,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'The printed label carries a real QR and Code 128; the blocks above are placeholders '
          'for position only.',
          style: body(size: 10.8, color: Brand.txt3, height: 1.45),
        ),
      ]),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.busy,
    required this.dirty,
    required this.onSave,
    required this.onReset,
  });

  final bool busy, dirty;
  final VoidCallback onSave, onReset;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.end,
        children: [
          if (dirty) GhostButton(label: 'Discard changes', onPressed: busy ? null : onReset),
          RibbonButton(
            label: busy ? 'Saving...' : 'Save label format',
            icon: Icons.save_outlined,
            onPressed: busy || !dirty ? null : onSave,
          ),
        ],
      );
}

/* ------------------------------------------------------------ line dialog */

class _LineDialog extends StatefulWidget {
  const _LineDialog({required this.line, required this.config, required this.sizes});

  final LabelTemplateLine? line;
  final LabelTemplateConfig config;
  final List<String> sizes;

  @override
  State<_LineDialog> createState() => _LineDialogState();
}

class _LineDialogState extends State<_LineDialog> {
  late final TextEditingController _caption =
      TextEditingController(text: widget.line?.label ?? '');
  late final TextEditingController _content =
      TextEditingController(text: widget.line?.token ?? '');
  late String _size = widget.line?.size ?? 'sm';

  @override
  void dispose() {
    _caption.dispose();
    _content.dispose();
    super.dispose();
  }

  Future<void> _insertToken() async {
    final token = await showDialog<String>(
      context: context,
      builder: (_) => _TokenPicker(config: widget.config),
    );
    if (token == null) return;
    final sel = _content.selection;
    final text = _content.text;
    final at = sel.isValid ? sel.start : text.length;
    final next = '${text.substring(0, at)}{$token}${text.substring(sel.isValid ? sel.end : text.length)}';
    setState(() {
      _content.text = next;
      _content.selection = TextSelection.collapsed(offset: at + token.length + 2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final index = widget.config.tokenIndex;
    return AlertDialog(
      title: Text(widget.line == null ? 'Add a line' : 'Edit line'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('A line prints an optional caption above its content. Content can mix plain text '
                'with fields in braces, so "{partNo} / {vendorCode}" prints both.',
                style: body(size: 11.5, color: Brand.txt3, height: 1.45)),
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerLeft, child: Text('CAPTION (OPTIONAL)', style: fieldLabel())),
            const SizedBox(height: 6),
            TextField(
              controller: _caption,
              decoration: const InputDecoration(hintText: 'e.g. LOCATION'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: Text('CONTENT', style: fieldLabel())),
              GhostButton(label: 'Insert field', small: true, onPressed: _insertToken),
            ]),
            const SizedBox(height: 6),
            TextField(
              controller: _content,
              decoration: const InputDecoration(hintText: '{partNo}'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerLeft, child: Text('SIZE', style: fieldLabel())),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              for (final s in widget.sizes)
                SelectChip(label: _sizeName(s), selected: _size == s, onTap: () => setState(() => _size = s)),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Brand.surface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Brand.line),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('PRINTS AS', style: eyebrow(size: 9.5, color: Brand.txt3)),
                const SizedBox(height: 6),
                if (_caption.text.trim().isNotEmpty)
                  Text(_caption.text.toUpperCase(), style: eyebrow(size: 9.5, color: Brand.txt3)),
                Text(
                  _content.text.trim().isEmpty ? '-' : resolveTokens(_content.text, index),
                  style: body(
                    size: _size == 'xl' ? 19 : (_size == 'lg' ? 16 : (_size == 'md' ? 13.5 : 12)),
                    weight: _size == 'xl' || _size == 'lg' ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _content.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    LabelTemplateLine(
                      label: _caption.text.trim().isEmpty ? null : _caption.text.trim(),
                      token: _content.text.trim(),
                      size: _size,
                    ),
                  ),
          child: Text(widget.line == null ? 'Add line' : 'Save line'),
        ),
      ],
    );
  }

  static String _sizeName(String s) => switch (s) {
        'xl' => 'Extra large',
        'lg' => 'Large',
        'md' => 'Medium',
        _ => 'Small',
      };
}

/* ------------------------------------------------------------ token picker */

class _TokenPicker extends StatefulWidget {
  const _TokenPicker({required this.config});

  final LabelTemplateConfig config;

  @override
  State<_TokenPicker> createState() => _TokenPickerState();
}

class _TokenPickerState extends State<_TokenPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final groups = [
      for (final g in widget.config.tokenGroups)
        (
          g.group,
          g.tokens
              .where((t) =>
                  q.isEmpty ||
                  t.label.toLowerCase().contains(q) ||
                  t.token.toLowerCase().contains(q) ||
                  (t.section ?? '').toLowerCase().contains(q))
              .toList(),
        ),
    ].where((e) => e.$2.isNotEmpty).toList();

    return AlertDialog(
      title: const Text('Insert a field'),
      content: SizedBox(
        width: 520,
        height: 460,
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Search part, vendor, packaging, calculated...',
              prefixIcon: Icon(Icons.search, size: 18),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: groups.isEmpty
                ? const EmptyState(message: 'No field matches that.')
                : ListView(
                    children: [
                      for (final (name, tokens) in groups) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
                          child: Text(name.toUpperCase(), style: eyebrow()),
                        ),
                        for (final t in tokens)
                          ListRow(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: InkWell(
                              onTap: () => Navigator.pop(context, t.token),
                              borderRadius: BorderRadius.circular(8),
                              child: Row(children: [
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(t.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: body(size: 12.8, weight: FontWeight.w700)),
                                    const SizedBox(height: 2),
                                    Text('{${t.token}}',
                                        style: mono(size: 10.8, color: Brand.pink)),
                                  ]),
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    t.example ?? '-',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.right,
                                    style: body(size: 11.5, color: Brand.txt3),
                                  ),
                                ),
                              ]),
                            ),
                          ),
                      ],
                    ],
                  ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}
