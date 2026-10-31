import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../storytel/storytel_http.dart';

/// Parent-facing login form. Arrow keys are never intercepted so the D-pad
/// stays on the on-screen keyboard; Next on the email moves to the password
/// and Done on the password logs in.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onLogin});

  final Future<void> Function(String email, String password) onLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  bool _busy = false;
  bool _rejected = false;
  bool _failed = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _rejected = false;
      _failed = false;
    });
    try {
      await widget.onLogin(_email.text, _password.text);
    } on StorytelAuthException {
      if (mounted) setState(() => _rejected = true);
      _refocusEmail();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
      _refocusEmail();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // After a failure the typos are fixed from the email field; the values stay.
  void _refocusEmail() {
    if (mounted) _emailFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          // A single column: the default reading-order traversal gives the
          // D-pad order email, password, button.
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.loginTitle,
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _email,
                focusNode: _emailFocus,
                onSubmitted: (_) => _passwordFocus.requestFocus(),
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.email,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _password,
                focusNode: _passwordFocus,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: l10n.password,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              if (_rejected || _failed) ...[
                Text(
                  _rejected ? l10n.loginRejected : l10n.loginFailed,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
              ],
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(l10n.loginButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
