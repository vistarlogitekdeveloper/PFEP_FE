import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../data/providers.dart';
import 'widgets/common.dart';

/// The prototype's `#login`: a brand panel on the left carrying the pitch, and
/// the sign-in form on the right. BRD 5 - customer PFEP data is confidential, so
/// the app is gated by a role-based login.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

/// The seeded demo accounts, one per role.
const _accounts = [
  ('admin', 'Admin', 'Masters, config, export'),
  ('sandeep', 'Field Collector', 'Collect data & photos'),
  ('reviewer', 'Reviewer', 'Approve submissions'),
  ('anita', 'Viewer', 'Dashboard & export'),
];

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _user = TextEditingController(text: 'admin');
  final _pass = TextEditingController(text: 'pfep1234');
  String _picked = 'admin';
  bool _obscure = true;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty || _pass.text.isEmpty) return;
    await ref.read(sessionProvider.notifier).signIn(_user.text.trim(), _pass.text);
  }

  void _pick(String username) {
    setState(() {
      _picked = username;
      _user.text = username;
      _pass.text = 'pfep1234';
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;

    return Scaffold(
      backgroundColor: Brand.bg,
      body: wide
          ? Row(children: [
              const Expanded(flex: 105, child: _ArtPanel()),
              Expanded(flex: 95, child: _form()),
            ])
          : _form(showWash: true),
    );
  }

  Widget _form({bool showWash = false}) {
    final session = ref.watch(sessionProvider);
    final light = ref.watch(themeModeProvider);

    final content = Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 52),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 392),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Image.asset('assets/brand/vistar_s.png',
                    width: 38, height: 41, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
              const SizedBox(height: 20),
              Text('Sign in to PFEP Studio', style: display(size: 26)),
              const SizedBox(height: 7),
              Text('Vistar Logitek · 3PL PFEP Programs', style: body(size: 13.5, color: Brand.txt3)),
              const SizedBox(height: 26),

              Text('USER ID', style: fieldLabel()),
              const SizedBox(height: 7),
              TextField(
                controller: _user,
                autofillHints: const [AutofillHints.username],
                textInputAction: TextInputAction.next,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 15),

              Text('PASSWORD', style: fieldLabel()),
              const SizedBox(height: 7),
              TextField(
                controller: _pass,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  suffixIcon: IconButton(
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 15),

              Text('SIGN IN AS', style: fieldLabel()),
              const SizedBox(height: 9),
              // .role-grid
              GridView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: 66,
                ),
                children: [
                  for (final (username, role, blurb) in _accounts)
                    _RoleChip(
                      role: role,
                      blurb: blurb,
                      selected: _picked == username,
                      onTap: () => _pick(username),
                    ),
                ],
              ),

              if (session.error != null) ...[
                const SizedBox(height: 16),
                AlertBox(tone: AlertTone.bad, title: session.error!),
              ],

              const SizedBox(height: 20),
              RibbonButton(
                label: 'Sign in',
                icon: Icons.arrow_forward_rounded,
                expand: true,
                busy: session.loading,
                onPressed: _submit,
              ),
              const SizedBox(height: 22),
              Text(
                'Demo build · every account uses the password pfep1234\n'
                'API: ${ref.watch(apiClientProvider).baseUrl}',
                textAlign: TextAlign.center,
                style: body(size: 11.5, color: Brand.txt3, height: 1.6),
              ),
            ],
          ),
        ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: showWash ? null : Brand.bg2,
        border: showWash ? null : Border(left: BorderSide(color: Brand.line)),
      ),
      child: Stack(children: [
        if (showWash) const Positioned.fill(child: _ArtWash()),
        content,
        Positioned(
          top: 18,
          right: 18,
          child: Tooltip(
            message: light ? 'Switch to dark' : 'Switch to light',
            child: InkWell(
              onTap: () => ref.read(themeModeProvider.notifier).toggle(),
              borderRadius: BorderRadius.circular(Brand.rSm),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Brand.surface,
                  border: Border.all(color: Brand.line),
                  borderRadius: BorderRadius.circular(Brand.rSm),
                ),
                child: Icon(light ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                    size: 17, color: Brand.txt2),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// `.role-chip` — the selected one is filled with the brand ribbon.
class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role, required this.blurb, required this.selected, required this.onTap});

  final String role, blurb;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Ink(
            decoration: BoxDecoration(
              gradient: selected ? Brand.ribbon : null,
              color: selected ? null : Brand.surface,
              border: Border.all(color: selected ? Colors.transparent : Brand.line),
              borderRadius: BorderRadius.circular(13),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: Brand.pink.withValues(alpha: 0.7),
                        blurRadius: 34,
                        spreadRadius: -16,
                        offset: const Offset(0, 14),
                      ),
                    ]
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(role,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: body(
                          size: 13.5,
                          weight: FontWeight.w800,
                          color: selected ? Colors.white : Brand.txt)),
                  const SizedBox(height: 3),
                  Text(blurb,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: body(
                        size: 11.5,
                        color: selected ? Colors.white.withValues(alpha: 0.85) : Brand.txt3,
                      )),
                ],
              ),
            ),
          ),
        ),
      );
}

/// `#login .art` — the brand panel: washes, the oversized S, the pitch, and the
/// three numbers that state what the app is for.
class _ArtPanel extends StatelessWidget {
  const _ArtPanel();

  @override
  Widget build(BuildContext context) => Stack(children: [
        const Positioned.fill(child: _ArtWash()),
        Positioned(
          left: -60,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Opacity(
              opacity: 0.16,
              child: Transform.rotate(
                angle: -0.19,
                child: Image.asset('assets/brand/vistar_s.png',
                    fit: BoxFit.contain, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 52),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Image.asset('assets/brand/vistar_s.png',
                  width: 46, height: 50, errorBuilder: (_, _, _) => const SizedBox.shrink()),
              const SizedBox(width: 8),
              Text('Vistar', style: display(size: 36, color: const Color(0xFFC81BBE))),
            ]),
            const Spacer(),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Every part.\nEvery detail. '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: ShaderMask(
                        shaderCallback: (r) => Brand.ribbon.createShader(r),
                        child: Text('Once',
                            style: display(size: 44, height: 1.08, color: Colors.white)),
                      ),
                    ),
                    const TextSpan(text: '.'),
                  ]),
                  style: display(size: 44, height: 1.08),
                ),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 452),
                  child: Text(
                    'Digital PFEP data collection at source - part, vendor, packaging, storage and '
                    'line-side data captured on site, every photo auto-tagged to the right part and '
                    'vendor, compiling straight into the customer PFEP Excel and print-ready labels.',
                    style: body(size: 14.5, color: Brand.txt2, height: 1.65),
                  ),
                ),
              ]),
            ),
            const Spacer(),
            const Wrap(spacing: 38, runSpacing: 18, children: [
              _ArtStat('0', 'Photos mismatched'),
              _ArtStat('0', 'Manual re-typing'),
              _ArtStat('1 tap', 'Excel & labels out'),
            ]),
          ]),
        ),
      ]);
}

class _ArtStat extends StatelessWidget {
  const _ArtStat(this.value, this.caption);

  final String value, caption;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          ShaderMask(
            shaderCallback: (r) => Brand.ribbon.createShader(r),
            child: Text(value, style: display(size: 27, color: Colors.white, height: 1)),
          ),
          const SizedBox(height: 7),
          Text(caption.toUpperCase(), style: eyebrow(size: 11, tracking: 0.8)),
        ],
      );
}

class _ArtWash extends StatelessWidget {
  const _ArtWash();

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: Brand.bg),
        child: Stack(children: [
          for (final (align, radius, color) in [
            (const Alignment(-0.64, -0.84), 1.1, Brand.purple.withValues(alpha: Brand.isLight ? 0.16 : 0.34)),
            (const Alignment(0.68, 0.84), 1.0, Brand.pink.withValues(alpha: Brand.isLight ? 0.12 : 0.24)),
            (const Alignment(0.92, -0.6), 0.9, Brand.orange.withValues(alpha: Brand.isLight ? 0.10 : 0.14)),
          ])
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: align,
                    radius: radius,
                    colors: [color, color.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
        ]),
      );
}
