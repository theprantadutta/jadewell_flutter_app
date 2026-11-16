import 'dart:async';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/api/api_result.dart';
import '../../../data/api/auth_api.dart';
import '../../../platform/analytics/analytics_service.dart';
import '../../../platform/auth/auth_service.dart';
import '../../../state/app_providers.dart';
import '../../../state/platform_providers.dart';
import '../../../state/session_controller.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../../widgets/widgets.dart';
import '../settings/screen_chrome.dart';
import 'email_sheet.dart';

/// Which sign-in method a button runs.
enum AccountMethod { google, apple, email }

/// Display-name rule shared with the backend (ProfileRules): 3–20 chars of
/// letters, digits, `_ . -` and single inner spaces.
abstract final class DisplayNames {
  static const minLength = 3;
  static const maxLength = 20;
  static final _pattern = RegExp(r'^[\p{L}\p{N}_.\-]+( [\p{L}\p{N}_.\-]+)*$', unicode: true);

  static bool isValid(String name) {
    final n = name.trim();
    return n.length >= minLength && n.length <= maxLength && _pattern.hasMatch(n);
  }
}

/// Friendly copy for an [AuthErrorKind]; null when nothing should be shown
/// (the player cancelled).
String? authErrorMessage(AppLocalizations l, AuthErrorKind kind) => switch (kind) {
      AuthErrorKind.cancelled => null,
      AuthErrorKind.credentialInUse => l.authErrorCredentialInUse,
      AuthErrorKind.emailInUse => l.authErrorEmailInUse,
      AuthErrorKind.invalidCredentials => l.authErrorInvalidCredentials,
      AuthErrorKind.weakPassword => l.authErrorWeakPassword,
      AuthErrorKind.invalidEmail => l.authErrorInvalidEmail,
      AuthErrorKind.network => l.authErrorNetwork,
      AuthErrorKind.unsupported => l.authErrorUnsupported,
      AuthErrorKind.unknown => l.authErrorUnknown,
    };

/// Human label for a Firebase provider id.
String providerLabel(AppLocalizations l, String provider) => switch (provider) {
      'google.com' => l.accountProviderGoogle,
      'apple.com' => l.accountProviderApple,
      'password' => l.accountProviderEmail,
      _ => provider,
    };

/// Account: profile (avatar, name, username, friend code) and either the
/// guest link options or the linked providers with Sign out.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  AccountMethod? _busy;
  bool _signingOut = false;

  /// Shown until the session's profile catches up after a rename.
  String? _nameOverride;

  bool get _showApple => defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final jw = context.jw;
    final haptic = ref.watch(hapticsProvider).selection;
    final sessionAsync = ref.watch(sessionProvider);
    final session = sessionAsync.value;
    final identity = session?.identity;
    final user = session?.user;
    final isGuest = identity?.isAnonymous ?? true;

    if (user != null && _nameOverride == user.displayName) _nameOverride = null;

    return JwPage(
      title: l.accountTitle,
      onHaptic: haptic,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 22, 16, 28 + MediaQuery.paddingOf(context).bottom),
        children: [
          _ProfileCard(
            user: user,
            displayName: _nameOverride ?? user?.displayName,
            loading: sessionAsync.isLoading && session == null,
            onEdit: user == null ? null : () => _editName(user),
            onRetry: () => ref.read(sessionProvider.notifier).ensureBackendSession(force: true),
            offline: session != null && user == null && session.lastFailure != null,
            onHaptic: haptic,
          ),
          if (isGuest) ...[
            JwEyebrow(l.accountKeepProgress),
            DecoratedBox(
              decoration: jw.clay(ClayLevel.raised, radius: 24),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const JwIconWell(icon: JwIcons.shield),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(l.accountGuestExplainer, style: jw.text.body.copyWith(fontSize: 15.5)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    JwBusyButton(
                      key: const ValueKey('account-google'),
                      label: l.accountContinueGoogle,
                      variant: JwButtonVariant.secondary,
                      busy: _busy == AccountMethod.google,
                      onHaptic: haptic,
                      onPressed: _busy == null ? () => _link(AccountMethod.google) : null,
                    ),
                    if (_showApple) ...[
                      const SizedBox(height: 12),
                      JwBusyButton(
                        key: const ValueKey('account-apple'),
                        label: l.accountContinueApple,
                        variant: JwButtonVariant.secondary,
                        busy: _busy == AccountMethod.apple,
                        onHaptic: haptic,
                        onPressed: _busy == null ? () => _link(AccountMethod.apple) : null,
                      ),
                    ],
                    const SizedBox(height: 12),
                    JwBusyButton(
                      key: const ValueKey('account-email'),
                      label: l.accountContinueEmail,
                      variant: JwButtonVariant.secondary,
                      busy: _busy == AccountMethod.email,
                      onHaptic: haptic,
                      onPressed: _busy == null ? _openEmail : null,
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            JwEyebrow(l.accountSignedInWith),
            JwListGroup(
              children: [
                for (final p in identity!.providers)
                  JwListRow(
                    icon: p == 'password' ? JwIcons.text : JwIcons.user,
                    title: providerLabel(l, p),
                    value: identity.email,
                    trailing: JwIcon(JwIcons.check, size: 20, color: jw.jade),
                  ),
              ],
            ),
            const SizedBox(height: 26),
            JwBusyButton(
              key: const ValueKey('account-signout'),
              label: l.accountSignOut,
              icon: JwIcons.door,
              variant: JwButtonVariant.secondary,
              busy: _signingOut,
              onHaptic: haptic,
              onPressed: _signOut,
            ),
          ],
        ],
      ),
    );
  }

  // ---- actions ----

  Future<void> _link(AccountMethod method) async {
    final l = AppLocalizations.of(context);
    final session = ref.read(sessionProvider.notifier);
    setState(() => _busy = method);
    try {
      await switch (method) {
        AccountMethod.google => session.linkGoogle(),
        AccountMethod.apple => session.linkApple(),
        AccountMethod.email => throw StateError('email links via the sheet'),
      };
      _linked(method);
    } on AuthException catch (e) {
      if (!mounted) return;
      if (e.kind == AuthErrorKind.credentialInUse) {
        setState(() => _busy = null);
        await _offerSignIn(method);
        return;
      }
      final message = authErrorMessage(l, e.kind);
      if (message != null) showJwToast(context, message, beadColor: context.jw.danger);
    } finally {
      if (mounted && _busy == method) setState(() => _busy = null);
    }
  }

  void _linked(AccountMethod method) {
    unawaited(ref.read(analyticsProvider).log(AnalyticsEvents.accountLinked, {'provider': method.name}));
    ref.read(hapticsProvider).success();
    if (mounted) showJwToast(context, AppLocalizations.of(context).accountLinkedToast);
  }

  /// The credential belongs to another Jadewell account: offer to switch to
  /// it, explaining this guest's progress stays behind.
  Future<void> _offerSignIn(AccountMethod method) async {
    final l = AppLocalizations.of(context);
    final ok = await showJwConfirm(
      context,
      title: l.accountInUseTitle,
      body: l.accountInUseBody,
      confirmLabel: l.accountSignInInstead,
      cancelLabel: l.commonCancel,
    );
    if (!ok || !mounted) return;
    final session = ref.read(sessionProvider.notifier);
    setState(() => _busy = method);
    try {
      await switch (method) {
        AccountMethod.google => session.signInWithGoogle(),
        AccountMethod.apple => session.signInWithApple(),
        AccountMethod.email => throw StateError('email signs in via the sheet'),
      };
      if (mounted) showJwToast(context, l.accountSignedInToast);
    } on AuthException catch (e) {
      final message = authErrorMessage(l, e.kind);
      if (mounted && message != null) showJwToast(context, message, beadColor: context.jw.danger);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _openEmail() async {
    final outcome = await showJwSheet<EmailSheetOutcome>(
      context,
      semanticLabel: AppLocalizations.of(context).accountContinueEmail,
      builder: (_) => const EmailSheet(),
    );
    if (!mounted || outcome == null) return;
    final l = AppLocalizations.of(context);
    switch (outcome) {
      case EmailSheetOutcome.linked:
        _linked(AccountMethod.email);
      case EmailSheetOutcome.signedIn:
        showJwToast(context, l.accountSignedInToast);
    }
  }

  Future<void> _signOut() async {
    final l = AppLocalizations.of(context);
    final ok = await showJwConfirm(
      context,
      title: l.accountSignOutTitle,
      body: l.accountSignOutBody,
      confirmLabel: l.accountSignOut,
      cancelLabel: l.commonCancel,
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _signingOut = true);
    try {
      await ref.read(sessionProvider.notifier).signOut();
    } on AuthException catch (e) {
      final message = authErrorMessage(l, e.kind);
      if (mounted && message != null) showJwToast(context, message, beadColor: context.jw.danger);
    } finally {
      if (mounted) setState(() => _signingOut = false);
    }
  }

  Future<void> _editName(BackendUser user) async {
    final saved = await showJwSheet<String>(
      context,
      semanticLabel: AppLocalizations.of(context).accountEditName,
      builder: (_) => _EditNameSheet(initial: _nameOverride ?? user.displayName),
    );
    if (saved == null || !mounted) return;
    setState(() => _nameOverride = saved);
    showJwToast(context, AppLocalizations.of(context).accountNameSaved);
    // Re-read the profile so the session (and everything showing the name)
    // picks the new name up.
    unawaited(ref.read(sessionProvider.notifier).refreshProfile());
  }
}

// ---- profile card ----

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.user,
    required this.displayName,
    required this.loading,
    required this.offline,
    required this.onEdit,
    required this.onRetry,
    this.onHaptic,
  });

  final BackendUser? user;
  final String? displayName;
  final bool loading;
  final bool offline;
  final VoidCallback? onEdit;
  final VoidCallback onRetry;
  final VoidCallback? onHaptic;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final jw = context.jw;
    final name = displayName ?? l.accountGuest;
    final code = user?.friendCode;
    return DecoratedBox(
      decoration: jw.clay(ClayLevel.raised, radius: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ProfileAvatar(name: name, color: avatarPastel(user?.avatarColor, jw), size: 68),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: jw.text.h2.copyWith(fontSize: 24), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text(
                        user == null
                            ? (offline ? l.accountOffline : l.accountConnecting)
                            : '@${user!.username}',
                        style: jw.text.body.copyWith(color: jw.textMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (onEdit != null)
                  JwIconButton(
                    icon: JwIcons.text,
                    semanticLabel: l.accountEditName,
                    size: 42,
                    iconSize: 19,
                    onHaptic: onHaptic,
                    onPressed: onEdit,
                  ),
              ],
            ),
            if (code != null) ...[
              const SizedBox(height: 18),
              FriendCodeRow(code: code, onHaptic: onHaptic),
            ] else if (offline && !loading) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: JwButton.secondary(
                  label: l.commonRetry,
                  icon: JwIcons.replay,
                  small: true,
                  onHaptic: onHaptic,
                  onPressed: onRetry,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Friend code  [JW-7K3P9Q]  Copy" in a sunken well.
class FriendCodeRow extends StatelessWidget {
  const FriendCodeRow({super.key, required this.code, this.onHaptic});

  final String code;
  final VoidCallback? onHaptic;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final jw = context.jw;
    Future<void> copy() async {
      await Clipboard.setData(ClipboardData(text: code));
      if (context.mounted) showJwToast(context, l.friendCodeCopied);
    }

    return DecoratedBox(
      decoration: jw.clay(ClayLevel.sunken, radius: 20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l.friendCodeLabel.toUpperCase(), style: jw.text.eyebrow.copyWith(fontSize: 11)),
                  const SizedBox(height: 2),
                  Semantics(
                    label: l.friendCodeSemantics(code.split('').join(' ')),
                    excludeSemantics: true,
                    child: Text(code, style: jw.text.numM.copyWith(fontSize: 19, letterSpacing: 1.2)),
                  ),
                ],
              ),
            ),
            JwButton.secondary(label: l.commonCopy, small: true, onHaptic: onHaptic, onPressed: copy),
          ],
        ),
      ),
    );
  }
}

/// Large avatar: initial on the profile's pastel, e1.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.name, this.color, this.size = 68});

  final String name;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: jw.clay(ClayLevel.chip, color: color ?? jw.accentSoft),
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: Text(
              initial,
              style: jw.text.h1.copyWith(fontSize: size * 0.42, color: const Color(0xFF4A3934)),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- edit name ----

class _EditNameSheet extends ConsumerStatefulWidget {
  const _EditNameSheet({required this.initial});

  final String initial;

  @override
  ConsumerState<_EditNameSheet> createState() => _EditNameSheetState();
}

class _EditNameSheetState extends ConsumerState<_EditNameSheet> {
  late final _controller = TextEditingController(text: widget.initial);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final name = _controller.text.trim();
    if (!DisplayNames.isValid(name)) {
      setState(() => _error = l.accountNameRule);
      return;
    }
    if (name == widget.initial) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final r = await ref.read(authApiProvider).updateProfile(displayName: name);
    if (!mounted) return;
    if (r.isSuccess) {
      Navigator.of(context).pop(r.value!.displayName);
      return;
    }
    setState(() {
      _saving = false;
      _error = switch (r.failure!) {
        ApiFailure.validation => r.message ?? l.accountNameRule,
        ApiFailure.offlineOrTransport || ApiFailure.timeout => l.commonOffline,
        _ => l.authErrorUnknown,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final jw = context.jw;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.accountEditName, style: jw.text.h3, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(l.accountNameHint, style: jw.text.body.copyWith(color: jw.textMuted), textAlign: TextAlign.center),
        const SizedBox(height: 18),
        JwTextField(
          controller: _controller,
          hint: l.accountNamePlaceholder,
          autofocus: true,
          maxLength: DisplayNames.maxLength,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          errorText: _error,
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 18),
        JwBusyButton(label: l.commonSave, busy: _saving, onPressed: _save),
      ],
    );
  }
}
