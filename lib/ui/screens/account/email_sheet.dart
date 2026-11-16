import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../platform/auth/auth_service.dart';
import '../../../state/app_providers.dart';
import '../../../state/platform_providers.dart';
import '../../../state/session_controller.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/jw_theme.dart';
import '../../widgets/widgets.dart';
import '../settings/screen_chrome.dart';
import 'account_screen.dart' show authErrorMessage;

enum EmailSheetOutcome { linked, signedIn }

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Email + password. By default it *links* the address to the guest (keeps
/// progress); "I already have an account" switches to signing in instead.
class EmailSheet extends ConsumerStatefulWidget {
  const EmailSheet({super.key, this.signIn = false});

  /// Start in sign-in mode.
  final bool signIn;

  @override
  ConsumerState<EmailSheet> createState() => _EmailSheetState();
}

class _EmailSheetState extends ConsumerState<EmailSheet> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  late bool _signIn = widget.signIn;
  bool _busy = false;
  bool _showPassword = false;
  String? _emailError;
  String? _passwordError;

  /// Inline notice under the fields (errors, or "reset link sent").
  String? _notice;
  bool _noticeIsError = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  bool _validate({bool passwordToo = true}) {
    final l = AppLocalizations.of(context);
    final email = _email.text.trim();
    setState(() {
      _emailError = _emailPattern.hasMatch(email) ? null : l.authErrorInvalidEmail;
      _passwordError = !passwordToo || _password.text.length >= 6 ? null : l.authErrorWeakPassword;
    });
    return _emailError == null && _passwordError == null;
  }

  Future<void> _submit() async {
    if (_busy || !_validate()) return;
    final l = AppLocalizations.of(context);
    final session = ref.read(sessionProvider.notifier);
    final email = _email.text.trim();
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      if (_signIn) {
        await session.signInWithEmail(email, _password.text);
        if (mounted) Navigator.of(context).pop(EmailSheetOutcome.signedIn);
      } else {
        await session.linkEmail(email, _password.text);
        if (mounted) Navigator.of(context).pop(EmailSheetOutcome.linked);
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (!_signIn && (e.kind == AuthErrorKind.emailInUse || e.kind == AuthErrorKind.credentialInUse)) {
          // The address already has an account: flip to sign in, with the
          // warning that this guest's progress won't come along.
          _signIn = true;
          _notice = l.emailInUseSwitch;
        } else {
          _notice = authErrorMessage(l, e.kind);
        }
        _noticeIsError = true;
      });
    }
  }

  Future<void> _forgot() async {
    if (_busy || !_validate(passwordToo: false)) return;
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await ref.read(authServiceProvider).sendPasswordReset(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _notice = l.emailResetSent;
        _noticeIsError = false;
      });
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _notice = authErrorMessage(l, e.kind);
        _noticeIsError = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final jw = context.jw;
    final haptic = ref.watch(hapticsProvider).selection;
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_signIn ? l.emailSignInTitle : l.emailLinkTitle, style: jw.text.h3, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Text(
            _signIn ? l.emailSignInBody : l.emailLinkBody,
            style: jw.text.body.copyWith(color: jw.textMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          JwTextField(
            key: const ValueKey('email-field'),
            controller: _email,
            label: l.emailLabel,
            hint: l.emailPlaceholder,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            textInputAction: TextInputAction.next,
            errorText: _emailError,
            onChanged: (_) {
              if (_emailError != null) setState(() => _emailError = null);
            },
          ),
          const SizedBox(height: 12),
          JwTextField(
            key: const ValueKey('password-field'),
            controller: _password,
            label: l.passwordLabel,
            hint: l.passwordPlaceholder,
            obscure: !_showPassword,
            autofillHints: [_signIn ? AutofillHints.password : AutofillHints.newPassword],
            textInputAction: TextInputAction.done,
            errorText: _passwordError,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_passwordError != null) setState(() => _passwordError = null);
            },
            trailing: Semantics(
              button: true,
              label: _showPassword ? l.passwordHide : l.passwordShow,
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _showPassword = !_showPassword),
                child: SizedBox(
                  width: 40,
                  height: 44,
                  child: Center(
                    child: JwIcon(JwIcons.eye, size: 20, color: _showPassword ? jw.accent : jw.textMuted),
                  ),
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            child: _notice == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        _notice!,
                        textAlign: TextAlign.center,
                        style: jw.text.callout.copyWith(color: _noticeIsError ? jw.danger : jw.jadeDeep),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 18),
          JwBusyButton(
            key: const ValueKey('email-submit'),
            label: _signIn ? l.emailSignInAction : l.emailLinkAction,
            busy: _busy,
            onHaptic: haptic,
            onPressed: _submit,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: JwButton.tertiary(
                  key: const ValueKey('email-mode'),
                  label: _signIn ? l.emailNewAccount : l.emailHaveAccount,
                  onHaptic: haptic,
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            _signIn = !_signIn;
                            _notice = null;
                          }),
                ),
              ),
              if (_signIn)
                Expanded(
                  child: JwButton.tertiary(
                    label: l.emailForgot,
                    onHaptic: haptic,
                    onPressed: _busy ? null : _forgot,
                  ),
                ),
            ],
          ),
          if (_signIn)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l.emailSignInWarning,
                textAlign: TextAlign.center,
                style: jw.text.caption.copyWith(fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}
