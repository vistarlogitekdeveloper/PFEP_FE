import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';

/// Shared components, each transcribed from a class in the approved prototype
/// (`design/prototype.html`). The comment above each one names the CSS class it
/// mirrors so the two can be kept in step.

/* --------------------------------------------------------------- formatting */

final _dateFmt = DateFormat('dd-MMM-yyyy');
final _timeFmt = DateFormat('HH:mm');
final _numFmt = NumberFormat.decimalPattern('en_IN');

String fmtDate(int? ms) => ms == null ? '-' : _dateFmt.format(DateTime.fromMillisecondsSinceEpoch(ms));
String fmtTime(int? ms) => ms == null ? '-' : _timeFmt.format(DateTime.fromMillisecondsSinceEpoch(ms));
String fmtDateTime(int? ms) => ms == null ? '-' : '${fmtDate(ms)}  ${fmtTime(ms)}';

String fmtNum(dynamic v) {
  if (v == null || v == '') return '-';
  final n = v is num ? v : num.tryParse('$v');
  if (n == null) return '$v';
  if (n == n.roundToDouble()) return _numFmt.format(n.round());
  return _numFmt.format(double.parse(n.toStringAsFixed(2)));
}

String fmtAgo(int? ms) {
  if (ms == null) return 'never';
  final d = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(ms));
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} hr ago';
  if (d.inDays < 30) return '${d.inDays} d ago';
  return fmtDate(ms);
}

/* -------------------------------------------------------------------- bits */

/// `.sect-ttl .acc` — the 5x16 ribbon tick before a section title.
class RibbonAccent extends StatelessWidget {
  const RibbonAccent({super.key, this.width = 5, this.height = 16});

  final double width, height;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: Brand.ribbon,
          borderRadius: BorderRadius.circular(6),
        ),
      );
}

/// `.sect-ttl` — accent tick, bold title, optional muted trailing note.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing, this.trailingWidget});

  final String title;
  final String? trailing;
  final Widget? trailingWidget;

  /// Under this width a title and a trailing *control* cannot share a line
  /// without the title losing - "Loaded parts" beside a 220px search box came
  /// out as "Load…" on a phone. Stack them instead. Desktop cards, even in a
  /// two-column grid, stay comfortably above it.
  static const _stackBelow = 380.0;

  Widget _heading() => Row(children: [
        const RibbonAccent(),
        const SizedBox(width: 9),
        // Expanded, not Flexible next to a Spacer. A Spacer is Expanded(flex: 1)
        // as well, so the two shared the free space evenly and the title was
        // capped at half the row however short the trailing was - which is what
        // turned "Collection progress" into "Collection …".
        Expanded(
          child: Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: body(size: 15, weight: FontWeight.w800)),
        ),
      ]);

  @override
  Widget build(BuildContext context) {
    final trail = trailingWidget ??
        (trailing == null
            ? null
            : Text(trailing!, style: body(size: 12.5, weight: FontWeight.w600, color: Brand.txt3)));

    if (trail == null) return _heading();

    return LayoutBuilder(
      builder: (context, box) {
        if (trailingWidget != null && box.maxWidth < _stackBelow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [_heading(), const SizedBox(height: 10), trail],
          );
        }
        return Row(children: [
          Expanded(child: _heading()),
          const SizedBox(width: 12),
          trail,
        ]);
      },
    );
  }
}

/// `.card` — gradient fill, hairline border, 16px radius, with the faint brand
/// swoosh bleeding out of the bottom-right corner (`.corner-s`).
class PfepCard extends StatelessWidget {
  const PfepCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.cornerMark = true,
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final bool cornerMark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: BoxDecoration(
        gradient: Brand.cardFill,
        border: Border.all(color: Brand.line),
        borderRadius: BorderRadius.circular(Brand.r),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        if (cornerMark)
          Positioned(
            right: -26,
            bottom: -30,
            width: 120,
            height: 120,
            child: IgnorePointer(
              child: Opacity(
                // A saturated mark reads much stronger over white than over
                // near-black, so the light theme needs a lighter hand.
                opacity: Brand.isLight ? 0.03 : 0.05,
                child: Image.asset('assets/brand/vistar_s.png',
                    errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            ),
          ),
        Padding(padding: padding, child: child),
      ]),
    );
    if (onTap == null) return card;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(Brand.r), child: card);
  }
}

/// A card with a `.sect-ttl` header. Replaces the old `Panel`.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.trailingText,
    this.padding = const EdgeInsets.all(18),
    this.cornerMark = true,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final String? trailingText;
  final EdgeInsets padding;
  final bool cornerMark;

  @override
  Widget build(BuildContext context) => PfepCard(
        padding: padding,
        cornerMark: cornerMark,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (title != null) ...[
            SectionTitle(title!, trailing: trailingText, trailingWidget: trailing),
            const SizedBox(height: 13),
          ],
          child,
        ]),
      );
}

/// `.pill`
class Pill extends StatelessWidget {
  const Pill(
    this.text, {
    super.key,
    this.tone,
    this.color,
    this.dot = false,
    this.icon,
    this.size = 11.5,
  });

  final String text;

  /// One of the prototype's `.p-*` classes. Preferred.
  final PillTone? tone;

  /// A brand colour, mapped to the nearest tone. Convenience for call sites
  /// that already think in terms of `Brand.ok` / `Brand.bad`.
  final Color? color;

  final bool dot;
  final IconData? icon;
  final double size;

  PillTone get _tone {
    if (tone != null) return tone!;
    return switch (color) {
      null => PillTone.neutral,
      final c when c == Brand.ok => PillTone.ok,
      final c when c == Brand.bad => PillTone.bad,
      final c when c == Brand.warn || c == Brand.amber => PillTone.amber,
      final c when c == Brand.info => PillTone.info,
      final c when c == Brand.pink => PillTone.pink,
      final c when c == Brand.violet || c == Brand.purple => PillTone.violet,
      final c when c == Brand.orange || c == Brand.orangeRed => PillTone.orange,
      _ => PillTone.neutral,
    };
  }

  @override
  Widget build(BuildContext context) {
    final t = _tone;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: t.fill,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (dot) ...[
          Container(width: 6, height: 6, decoration: BoxDecoration(color: t.dot, shape: BoxShape.circle)),
          const SizedBox(width: 6),
        ] else if (icon != null) ...[
          Icon(icon, size: size + 1, color: t.ink),
          const SizedBox(width: 6),
        ],
        Text(text, style: body(size: size, weight: FontWeight.w700, color: t.ink)),
      ]),
    );
  }
}

/// Status pill, using the prototype's tone mapping.
class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key, this.compact = false});

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) =>
      Pill(status, tone: Brand.statusTone(status), dot: true, size: compact ? 10.5 : 11.5);
}

/// `.avatar` — ribbon fill, 11px radius, initials in white.
class Avatar extends StatelessWidget {
  const Avatar(this.initials, {super.key, this.size = 34});

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: Brand.ribbon,
          borderRadius: BorderRadius.circular(size * 0.32),
        ),
        alignment: Alignment.center,
        child: Text(
          initials,
          style: body(
            size: size * 0.37,
            weight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 0.3,
          ),
        ),
      );
}

/// `.phead` — "SETUP · **FIELD CONFIG**" crumb where the accent half is filled
/// with the brand ribbon, a Bricolage headline, a muted blurb and right-aligned
/// actions.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.crumb,
    required this.accent,
    required this.title,
    this.blurb,
    this.blurbHighlight,
    this.actions = const [],
  });

  /// The muted first half of the crumb, e.g. "Setup ·".
  final String crumb;

  /// The ribbon-filled half of the crumb, e.g. "Field Config".
  final String accent;

  final String title;
  final String? blurb;

  /// Rendered bold inside the blurb, as `<b>` does in the prototype.
  final String? blurbHighlight;

  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 760;

    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('${crumb.toUpperCase()} ', style: eyebrow(size: 11.5, tracking: 0.7)),
          ShaderMask(
            shaderCallback: (r) => Brand.ribbon.createShader(r),
            child: Text(accent.toUpperCase(),
                style: eyebrow(size: 11.5, tracking: 0.7, color: Colors.white)),
          ),
        ]),
        const SizedBox(height: 9),
        Text(title, style: display(size: narrow ? 23 : 29)),
        if (blurb != null) ...[
          const SizedBox(height: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660),
            child: _blurbText(),
          ),
        ],
      ],
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: narrow
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              head,
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 14),
                Wrap(spacing: 9, runSpacing: 9, children: actions),
              ],
            ])
          : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: head),
              const SizedBox(width: 18),
              Wrap(spacing: 9, runSpacing: 9, children: actions),
            ]),
    );
  }

  Widget _blurbText() {
    final style = body(size: 13.5, color: Brand.txt3, height: 1.55);
    if (blurbHighlight == null || !blurb!.contains(blurbHighlight!)) {
      return Text(blurb!, style: style);
    }
    final parts = blurb!.split(blurbHighlight!);
    return RichText(
      text: TextSpan(style: style, children: [
        TextSpan(text: parts.first),
        TextSpan(
          text: blurbHighlight,
          style: body(size: 13.5, weight: FontWeight.w800, color: Brand.txt2, height: 1.55),
        ),
        TextSpan(text: parts.length > 1 ? parts.sublist(1).join(blurbHighlight!) : ''),
      ]),
    );
  }
}

/// `.card.kpi` — icon chip, big Bricolage value, muted caption.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.accent,
    this.icon,
    this.onTap,
    this.trailing,
    this.gradientValue = false,
  });

  final String label;
  final String value;
  final String? sub;
  final Color? accent;
  final IconData? icon;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Fills the number with the brand ribbon, as `.val.grad` does.
  final bool gradientValue;

  @override
  Widget build(BuildContext context) {
    final tone = accent ?? Brand.pink;
    final number = Text(value, style: display(size: 30, color: gradientValue ? Colors.white : tone));

    return PfepCard(
      onTap: onTap,
      padding: const EdgeInsets.all(18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon ?? Icons.circle_outlined, size: 18, color: tone),
          ),
          const Spacer(),
          ?trailing,
        ]),
        const SizedBox(height: 14),
        if (gradientValue)
          ShaderMask(shaderCallback: (r) => Brand.ribbon.createShader(r), child: number)
        else
          number,
        const SizedBox(height: 6),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: body(size: 12, weight: FontWeight.w600, color: Brand.txt3)),
        if (sub != null) ...[
          const SizedBox(height: 3),
          Text(sub!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: body(size: 11.5, color: Brand.txt3, height: 1.35)),
        ],
      ]),
    );
  }
}

/// `.alertbox`
class AlertBox extends StatelessWidget {
  const AlertBox({
    super.key,
    required this.tone,
    required this.title,
    this.message = '',
    this.icon,
  });

  final AlertTone tone;
  final String title;
  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(
          color: tone.fill,
          border: Border.all(color: tone.border),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon ?? _defaultIcon, size: 16, color: tone.icon),
          const SizedBox(width: 11),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: body(size: 13, weight: FontWeight.w800, color: tone.ink)),
              if (message.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(message,
                    style: body(
                        size: 13, color: tone.ink.withValues(alpha: 0.86), height: 1.55)),
              ],
            ]),
          ),
        ]),
      );

  IconData get _defaultIcon => switch (tone) {
        AlertTone.bad => Icons.error_outline,
        AlertTone.ok => Icons.verified_outlined,
        AlertTone.warn => Icons.warning_amber_rounded,
        AlertTone.info => Icons.shield_outlined,
      };
}

/// `.listrow`
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Ink(
            decoration: BoxDecoration(
              color: Brand.surface,
              border: Border.all(color: Brand.line),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
}

/// `.btn-grad` — the ribbon-filled primary action.
class RibbonButton extends StatelessWidget {
  const RibbonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.expand = false,
    this.small = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final bool expand;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          borderRadius: BorderRadius.circular(small ? 10 : Brand.rSm),
          child: Ink(
            decoration: BoxDecoration(
              gradient: Brand.ribbon,
              borderRadius: BorderRadius.circular(small ? 10 : Brand.rSm),
              boxShadow: [
                BoxShadow(
                  color: Brand.pink.withValues(alpha: 0.55),
                  blurRadius: 34,
                  spreadRadius: -14,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: small ? 14 : 18, vertical: small ? 9 : 13),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (busy)
                    const SizedBox(
                        width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  else if (icon != null)
                    Icon(icon, size: small ? 15 : 17, color: Colors.white),
                  if (busy || icon != null) const SizedBox(width: 9),
                  Text(label,
                      style: body(
                          size: small ? 13 : 14, weight: FontWeight.w700, color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `.btn-ghost`
class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.small = false,
    this.danger = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool small;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final ink = danger ? Brand.bad : Brand.txt;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(small ? 9 : 10),
        child: Ink(
          decoration: BoxDecoration(
            color: danger ? Brand.bad.withValues(alpha: 0.13) : Brand.surface2,
            border: Border.all(color: danger ? Brand.bad.withValues(alpha: 0.28) : Brand.line),
            borderRadius: BorderRadius.circular(small ? 9 : 10),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: small ? 10 : 14, vertical: small ? 6 : 11),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[Icon(icon, size: small ? 13 : 15, color: ink), const SizedBox(width: 7)],
              Text(label, style: body(size: small ? 12 : 13, weight: FontWeight.w700, color: ink)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// `.chip`
class SelectChip extends StatelessWidget {
  const SelectChip({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            decoration: BoxDecoration(
              color: selected ? Brand.pink.withValues(alpha: 0.14) : Brand.surface2,
              border: Border.all(
                color: selected ? Brand.pink.withValues(alpha: 0.42) : Brand.line,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              child: Text(label,
                  style: body(
                    size: 12.5,
                    weight: FontWeight.w700,
                    color: selected ? PillTone.pink.ink : Brand.txt2,
                  )),
            ),
          ),
        ),
      );
}

/// `.seg`
class Segmented extends StatelessWidget {
  const Segmented({super.key, required this.options, required this.value, required this.onChanged});

  final List<(String value, String label)> options;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Brand.surface2,
          border: Border.all(color: Brand.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (v, label) in options)
            InkWell(
              onTap: () => onChanged(v),
              borderRadius: BorderRadius.circular(9),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                decoration: BoxDecoration(
                  color: v == value ? Brand.surface3 : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(label,
                    style: body(
                      size: 12.5,
                      weight: FontWeight.w700,
                      color: v == value ? Brand.txt : Brand.txt3,
                    )),
              ),
            ),
        ]),
      );
}

/// `.bar`
class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.value, this.color, this.height = 7, this.ribbon = true});

  final double value;
  final Color? color;
  final double height;

  /// The prototype fills progress with the ribbon; pass false for a solid tone.
  final bool ribbon;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: height,
          color: Brand.track,
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0, 1),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: ribbon && color == null ? Brand.ribbon : null,
                color: color,
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ),
      );
}

/// `.stepper` / `.step`
class StepStrip extends StatelessWidget {
  const StepStrip({super.key, required this.labels, required this.current, this.onTap});

  final List<String> labels;
  final int current;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < labels.length; i++) ...[
            InkWell(
              onTap: onTap == null ? null : () => onTap!(i),
              borderRadius: BorderRadius.circular(9),
              child: Padding(
                padding: const EdgeInsets.only(right: 14, top: 4, bottom: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: i == current ? Brand.ribbon : null,
                      color: i == current
                          ? null
                          : (i < current ? Brand.ok.withValues(alpha: 0.14) : Brand.surface2),
                      border: Border.all(
                        color: i == current
                            ? Colors.transparent
                            : (i < current ? Brand.ok.withValues(alpha: 0.3) : Brand.line),
                      ),
                      borderRadius: BorderRadius.circular(9),
                      boxShadow: i == current
                          ? [
                              BoxShadow(
                                color: Brand.pink.withValues(alpha: 0.7),
                                blurRadius: 20,
                                spreadRadius: -10,
                                offset: const Offset(0, 8),
                              ),
                            ]
                          : null,
                    ),
                    child: i < current
                        ? Icon(Icons.check, size: 13, color: Brand.ok)
                        : Text('${i + 1}',
                            style: body(
                              size: 11.5,
                              weight: FontWeight.w800,
                              color: i == current ? Colors.white : Brand.txt3,
                            )),
                  ),
                  const SizedBox(width: 9),
                  Text(labels[i],
                      style: body(
                        size: 12.5,
                        weight: FontWeight.w700,
                        color: i == current ? Brand.txt : (i < current ? Brand.txt2 : Brand.txt3),
                      )),
                ]),
              ),
            ),
            if (i < labels.length - 1)
              Container(width: 26, height: 1.5, color: Brand.line, margin: const EdgeInsets.only(right: 14)),
          ],
        ]),
      );
}

/// `.empty` — includes the faded brand mark the prototype uses.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.message, this.icon, this.action});

  final String message;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 44, horizontal: 20),
        child: Column(children: [
          if (icon != null)
            Icon(icon, size: 32, color: Brand.txt3)
          else
            Opacity(
              opacity: 0.28,
              child: Image.asset('assets/brand/vistar_s.png',
                  width: 56, errorBuilder: (_, _, _) => const SizedBox.shrink()),
            ),
          const SizedBox(height: 14),
          Text(message,
              textAlign: TextAlign.center,
              style: body(size: 13.5, color: Brand.txt3, height: 1.55)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      );
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.wifi_off_rounded, size: 32, color: Brand.bad),
          const SizedBox(height: 12),
          Text('$error',
              textAlign: TextAlign.center,
              style: body(size: 13, color: Brand.txt2, height: 1.5)),
          if (onRetry != null) ...[
            const SizedBox(height: 16),
            GhostButton(label: 'Try again', icon: Icons.refresh, onPressed: onRetry),
          ],
        ]),
      );
}

/// The splash/route loader: the brand mark breathing inside two orbit rings.
class Loading extends StatefulWidget {
  const Loading({super.key, this.label});

  final String? label;

  @override
  State<Loading> createState() => _LoadingState();
}

class _LoadingState extends State<Loading> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(children: [
          SizedBox(
            width: 64,
            height: 64,
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, _) => Stack(alignment: Alignment.center, children: [
                Transform.rotate(
                  angle: _c.value * 6.283,
                  child: CustomPaint(size: const Size(64, 64), painter: _RingPainter(Brand.pink, Brand.orange)),
                ),
                Transform.rotate(
                  angle: -_c.value * 4.6,
                  child: CustomPaint(size: const Size(42, 42), painter: _RingPainter(Brand.violet, Brand.amber)),
                ),
                Transform.scale(
                  scale: 0.92 + 0.12 * (0.5 + 0.5 * (1 - (2 * _c.value - 1).abs())),
                  child: Image.asset('assets/brand/vistar_s.png',
                      width: 24, errorBuilder: (_, _, _) => const SizedBox.shrink()),
                ),
              ]),
            ),
          ),
          if (widget.label != null) ...[
            const SizedBox(height: 16),
            Text(widget.label!, style: body(size: 12.5, color: Brand.txt3)),
          ],
        ]),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.a, this.b);

  final Color a, b;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect.deflate(1), -1.57, 1.4, false, p..color = a.withValues(alpha: 0.65));
    canvas.drawArc(rect.deflate(1), 0.6, 1.1, false, p..color = b.withValues(alpha: 0.45));
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.a != a || old.b != b;
}

/// Key/value row used across the record detail and review screens.
class KvRow extends StatelessWidget {
  const KvRow(this.label, this.value, {super.key, this.valueColor, this.monospace = false});

  final String label;
  final String value;
  final Color? valueColor;

  /// Tabular figures, for numbers that should align down a column.
  final bool monospace;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 160,
            child: Text(label, style: body(size: 12, color: Brand.txt3, height: 1.4)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: monospace
                  ? mono(size: 12.5, color: valueColor)
                  : body(size: 12.8, weight: FontWeight.w600, color: valueColor, height: 1.4),
            ),
          ),
        ]),
      );
}

/// `.toast` — a left ribbon strip, a tinted icon chip, title and detail.
void showToast(BuildContext context, String message, {bool error = false, bool warn = false, String? detail}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final tone = error ? Brand.bad : (warn ? Brand.amber : Brand.ok);
  messenger.clearSnackBars();
  messenger.showSnackBar(SnackBar(
    duration: Duration(seconds: error ? 6 : 4),
    padding: EdgeInsets.zero,
    backgroundColor: Colors.transparent,
    elevation: 0,
    content: Container(
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        color: Brand.surface3,
        border: Border.all(color: Brand.line2),
        borderRadius: BorderRadius.circular(14),
        boxShadow: Brand.shadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 3, decoration: BoxDecoration(gradient: Brand.ribbon)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(13, 13, 15, 13),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    error ? Icons.error_outline : (warn ? Icons.warning_amber_rounded : Icons.check),
                    size: 15,
                    color: tone,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(message, style: body(size: 13.5, weight: FontWeight.w800)),
                    if (detail != null) ...[
                      const SizedBox(height: 2),
                      Text(detail, style: body(size: 12.5, color: Brand.txt2, height: 1.45)),
                    ],
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
    ),
  ));
}

/// `.tbl-wrap` — sticky-looking header on `--surface2`, hairline row rules, and
/// horizontal scrolling inside the card so the page never scrolls sideways.
///
/// The table is given a **minimum** width of the card it sits in. Inside a
/// horizontal scroll view the constraints are unbounded, so a DataTable would
/// otherwise size to its intrinsic content: on a wide screen the header band and
/// the row rules stopped short of the card's right edge and left a dead strip.
/// Holding it to at least the available width makes the columns share the slack
/// on desktop, while anything genuinely wider than the viewport - which is every
/// one of these tables on a phone - still scrolls.
class ScrollTable extends StatefulWidget {
  const ScrollTable({
    super.key,
    required this.columns,
    required this.rows,
    this.emptyMessage = 'Nothing here yet.',
  });

  final List<DataColumn> columns;
  final List<DataRow> rows;
  final String emptyMessage;

  @override
  State<ScrollTable> createState() => _ScrollTableState();
}

class _ScrollTableState extends State<ScrollTable> {
  // A Scrollbar needs its own controller here, because this view is not the
  // primary scrollable - the page behind it is. Without one, a table that
  // overflows on a narrow window gives no hint that there is more to the right.
  final _h = ScrollController();

  @override
  void dispose() {
    _h.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.rows.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: Brand.surface,
          borderRadius: BorderRadius.circular(Brand.r),
          border: Border.all(color: Brand.line),
        ),
        child: EmptyState(message: widget.emptyMessage),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Brand.surface,
        borderRadius: BorderRadius.circular(Brand.r),
        border: Border.all(color: Brand.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, box) => Scrollbar(
          controller: _h,
          scrollbarOrientation: ScrollbarOrientation.bottom,
          child: SingleChildScrollView(
            controller: _h,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: box.maxWidth),
              child: DataTable(
                columns: widget.columns,
                rows: widget.rows,
                headingRowHeight: 44,
                dataRowMinHeight: 46,
                dataRowMaxHeight: 62,
                horizontalMargin: 16,
                columnSpacing: 26,
                headingRowColor: WidgetStatePropertyAll(Brand.surface2),
                headingTextStyle: eyebrow(size: 11, tracking: 0.6, color: Brand.txt3),
                dataTextStyle: body(size: 13, color: Brand.txt2),
                dividerThickness: 1,
                border: TableBorder(horizontalInside: BorderSide(color: Brand.line)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
