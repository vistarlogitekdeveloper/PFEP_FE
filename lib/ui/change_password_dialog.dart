import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api.dart';
import '../core/theme.dart';
import '../data/providers.dart';
import 'widgets/common.dart';

/// The one client-side minimum, kept equal to the backend's
/// `config.passwordMinLength` (8). Shared with the admin user form so both
/// places agree with the server and with each other.
const int kPasswordMinLength = 8;

/// Opens the self-service Change Password dialog.
Future<void> showChangePasswordDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const ChangePasswordDialog());

class ChangePasswordDialog extends ConsumerStatefulWidget {
  const ChangePasswordDialog({super.key});

  @override
  ConsumerState<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends ConsumerState<ChangePasswordDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  // Caught before the round trip so the obvious mistakes answer instantly; the
  // backend still has the final say (it owns the policy and the current-password
  // check), and those answers surface through the ApiException branch below.
  String? _localProblem() {
    if (_current.text.isEmpty) return 'Enter your current password.';
    if (_next.text.length < kPasswordMinLength) {
      return 'The new password must be at least $kPasswordMinLength characters.';
    }
    if (_next.text != _confirm.text) return 'The new passwords do not match.';
    return null;
  }

  Future<void> _submit() async {
    final problem = _localProblem();
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(repositoryProvider).changePassword(_current.text, _next.text);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed.')),
      );
    } on ApiException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Change password'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _field('CURRENT PASSWORD', _current),
            const SizedBox(height: 12),
            _field('NEW PASSWORD', _next),
            const SizedBox(height: 6),
            Text('At least $kPasswordMinLength characters.', style: body(size: 11.5, color: Brand.txt3)),
            const SizedBox(height: 12),
            _field('CONFIRM NEW PASSWORD', _confirm, onSubmit: _submit),
            if (_error != null) ...[
              const SizedBox(height: 14),
              AlertBox(tone: AlertTone.bad, title: _error!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Update'),
        ),
      ],
    );
  }

  Widget _field(String label, TextEditingController c, {VoidCallback? onSubmit}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: fieldLabel()),
          const SizedBox(height: 6),
          TextField(
            controller: c,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
            decoration: InputDecoration(
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
        ],
      );
}
