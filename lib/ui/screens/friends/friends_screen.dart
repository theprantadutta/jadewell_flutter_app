import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/api/api_result.dart';
import '../../../data/repositories/social_repository.dart';
import '../../../state/platform_providers.dart';
import '../../../state/session_controller.dart';
import '../../../state/social_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../../widgets/skeleton/jw_skeleton.dart';
import '../../widgets/widgets.dart';
import '../account/account_screen.dart' show FriendCodeRow;
import '../settings/screen_chrome.dart';

/// Formats the add-friend field as the player types: uppercase, Crockford
/// look-alikes mapped, `JW-` prefix, at most 6 code characters.
class FriendCodeInputFormatter extends TextInputFormatter {
  const FriendCodeInputFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // Deleting into the prefix clears the field rather than fighting it.
    if (newValue.text.length < oldValue.text.length && newValue.text.length <= FriendCodes.prefix.length) {
      return const TextEditingValue();
    }
    final pasted = FriendCodes.normalize(newValue.text);
    final text = pasted ?? FriendCodes.formatPartial(newValue.text);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// Friends: your code + invite link, add by code, requests, friends list.
class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  final _code = TextEditingController();
  String? _codeError;
  bool _sending = false;
  bool _retrying = false;
  final Set<String> _busyIds = {};

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final jw = context.jw;
    final haptic = ref.watch(hapticsProvider).selection;
    final user = ref.watch(sessionProvider).value?.user;
    final friendsAsync = ref.watch(friendsProvider);
    final view = friendsAsync.value;

    return JwPage(
      title: l.friendsTitle,
      onHaptic: haptic,
      child: RefreshIndicator(
        color: jw.accent,
        backgroundColor: jw.surfaceRaised,
        onRefresh: () => ref.read(friendsProvider.notifier).refresh(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(16, 4, 16, 28 + MediaQuery.paddingOf(context).bottom),
          children: [
            JwEyebrow(l.friendsYourCode, top: 22),
            _card(
              context,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (user != null)
                    FriendCodeRow(code: user.friendCode, onHaptic: haptic)
                  else
                    Text(l.friendsCodeUnavailable, style: jw.text.body.copyWith(color: jw.textMuted)),
                  const SizedBox(height: 12),
                  Text(l.friendsShareHint, style: jw.text.body.copyWith(color: jw.textMuted)),
                  const SizedBox(height: 14),
                  JwButton.secondary(
                    key: const ValueKey('friends-invite'),
                    label: l.friendsCopyInvite,
                    icon: JwIcons.heart,
                    expand: true,
                    onHaptic: haptic,
                    onPressed: user == null ? null : () => _copyInvite(user.friendCode),
                  ),
                ],
              ),
            ),
            JwEyebrow(l.friendsAddTitle),
            _card(
              context,
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  JwTextField(
                    key: const ValueKey('friends-code-field'),
                    controller: _code,
                    hint: 'JW-XXXXXX',
                    mono: true,
                    keyboardType: TextInputType.visiblePassword,
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: const [FriendCodeInputFormatter()],
                    textInputAction: TextInputAction.send,
                    errorText: _codeError,
                    onChanged: (_) {
                      if (_codeError != null) setState(() => _codeError = null);
                    },
                    onSubmitted: (_) => _send(),
                  ),
                  const SizedBox(height: 14),
                  JwBusyButton(
                    key: const ValueKey('friends-send'),
                    label: l.friendsSendRequest,
                    icon: JwIcons.arrow,
                    busy: _sending,
                    onHaptic: haptic,
                    onPressed: _send,
                  ),
                ],
              ),
            ),
            ..._lists(context, view, friendsAsync.isLoading, haptic),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, Widget child) => DecoratedBox(
        decoration: context.jw.clay(ClayLevel.raised, radius: 24),
        child: Padding(padding: const EdgeInsets.all(18), child: child),
      );

  List<Widget> _lists(BuildContext context, FriendsView? view, bool loading, VoidCallback haptic) {
    final l = AppLocalizations.of(context);
    final jw = context.jw;
    if (view == null) {
      return [
        const SizedBox(height: 26),
        JwSkeletonSwitcher(
          loading: true,
          skeleton: const JwSkeletonScope(
            child: Column(
              children: [
                JwSkeletonBox(height: 56, radius: 20),
                SizedBox(height: 10),
                JwSkeletonBox(height: 56, radius: 20),
              ],
            ),
          ),
          builder: (_) => const SizedBox.shrink(),
        ),
      ];
    }
    final out = <Widget>[];
    if (view.hasFailure) {
      final offline = view.failure == ApiFailure.offlineOrTransport || view.failure == ApiFailure.timeout;
      out
        ..add(const SizedBox(height: 26))
        ..add(
          JwNoticeCard(
            icon: offline ? JwIcons.restore : JwIcons.info,
            title: offline ? l.commonOfflineTitle : l.friendsUnavailableTitle,
            body: offline ? l.friendsOfflineBody : l.friendsUnavailableBody,
            actionLabel: l.commonRetry,
            busy: _retrying || loading,
            onHaptic: haptic,
            onAction: _retry,
          ),
        );
      if (!view.loaded) return out;
    }

    if (view.incoming.isNotEmpty || view.outgoing.isNotEmpty) {
      out
        ..add(JwEyebrow(l.friendsRequests))
        ..add(
          JwListGroup(
            children: [
              for (final r in view.incoming) _incomingRow(context, r, haptic),
              for (final r in view.outgoing) _outgoingRow(context, r, haptic),
            ],
          ),
        );
    }

    out.add(JwEyebrow(l.friendsListTitle(view.friends.length)));
    if (view.friends.isEmpty) {
      out.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(l.friendsEmpty, style: jw.text.body.copyWith(color: jw.textMuted)),
        ),
      );
    } else {
      out.add(JwListGroup(children: [for (final f in view.friends) _friendRow(context, f, haptic)]));
    }
    return out;
  }

  Widget _person(BuildContext context, PlayerSummary p, {String? sub, required Widget trailing}) {
    final jw = context.jw;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 62),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 9, 10, 9),
        child: Row(
          children: [
            JwAvatar(name: p.displayName, color: avatarPastel(p.avatarColor, jw)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(p.displayName, maxLines: 1, overflow: TextOverflow.ellipsis, style: jw.text.body.copyWith(fontSize: 16.5)),
                  if (sub != null)
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: jw.text.caption.copyWith(fontSize: 13.5)),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _incomingRow(BuildContext context, FriendRequest r, VoidCallback haptic) {
    final l = AppLocalizations.of(context);
    final busy = _busyIds.contains(r.id);
    return _person(
      context,
      r.player,
      sub: l.friendsWantsToAdd,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          JwIconButton(
            icon: JwIcons.x,
            semanticLabel: l.friendsDecline(r.player.displayName),
            size: 40,
            iconSize: 18,
            onHaptic: haptic,
            onPressed: busy ? null : () => _act(r.id, () => ref.read(friendsProvider.notifier).decline(r)),
          ),
          const SizedBox(width: 8),
          JwButton.primary(
            label: l.friendsAccept,
            small: true,
            semanticLabel: l.friendsAcceptSemantics(r.player.displayName),
            onHaptic: haptic,
            onPressed: busy
                ? null
                : () => _act(r.id, () => ref.read(friendsProvider.notifier).accept(r), success: l.friendsAccepted(r.player.displayName)),
          ),
        ],
      ),
    );
  }

  Widget _outgoingRow(BuildContext context, FriendRequest r, VoidCallback haptic) {
    final l = AppLocalizations.of(context);
    final busy = _busyIds.contains(r.id);
    return _person(
      context,
      r.player,
      sub: l.friendsPending,
      trailing: JwButton.tertiary(
        label: l.commonCancel,
        small: true,
        semanticLabel: l.friendsCancelSemantics(r.player.displayName),
        onHaptic: haptic,
        onPressed: busy ? null : () => _act(r.id, () => ref.read(friendsProvider.notifier).cancel(r)),
      ),
    );
  }

  Widget _friendRow(BuildContext context, Friend f, VoidCallback haptic) {
    final l = AppLocalizations.of(context);
    final busy = _busyIds.contains(f.userId);
    final row = _person(
      context,
      f.player,
      sub: f.player.username == null ? null : '@${f.player.username}',
      trailing: JwIconButton(
        icon: JwIcons.trash,
        semanticLabel: l.friendsRemoveSemantics(f.player.displayName),
        size: 40,
        iconSize: 18,
        color: context.jw.textMuted,
        onHaptic: haptic,
        onPressed: busy ? null : () => _remove(f),
      ),
    );
    return Dismissible(
      key: ValueKey('friend-${f.userId}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _remove(f),
      background: ColoredBox(
        color: context.jw.danger.withValues(alpha: 0.18),
        child: Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 22),
            child: JwIcon(JwIcons.trash, color: context.jw.danger),
          ),
        ),
      ),
      child: row,
    );
  }

  // ---- actions ----

  Future<void> _copyInvite(String code) async {
    // TODO(share_plus): open the share sheet with this text instead.
    final l = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: l.friendsInviteText(FriendCodes.inviteLink(code))));
    if (mounted) showJwToast(context, l.friendsInviteCopied);
  }

  Future<void> _send() async {
    if (_sending) return;
    final l = AppLocalizations.of(context);
    final code = FriendCodes.normalize(_code.text);
    if (code == null) {
      setState(() => _codeError = l.friendsErrorInvalid);
      return;
    }
    setState(() {
      _sending = true;
      _codeError = null;
    });
    final r = await ref.read(friendsProvider.notifier).sendRequest(code);
    if (!mounted) return;
    setState(() => _sending = false);
    if (r.error == null) {
      _code.clear();
      FocusScope.of(context).unfocus();
      final name = r.request?.player.displayName ?? code;
      showJwToast(
        context,
        r.request?.status == FriendRequestStatus.accepted ? l.friendsAccepted(name) : l.friendsRequestSent(name),
      );
      ref.read(hapticsProvider).success();
      return;
    }
    setState(() {
      _codeError = switch (r.error!) {
        AddFriendError.invalidCode => l.friendsErrorInvalid,
        AddFriendError.ownCode => l.friendsErrorOwnCode,
        AddFriendError.notFound => l.friendsErrorNotFound,
        AddFriendError.alreadyConnected => l.friendsErrorAlready,
        AddFriendError.offline => l.commonOffline,
        AddFriendError.unavailable => l.friendsErrorUnavailable,
      };
    });
  }

  Future<void> _act(String id, Future<bool> Function() action, {String? success}) async {
    final l = AppLocalizations.of(context);
    setState(() => _busyIds.add(id));
    final ok = await action();
    if (!mounted) return;
    setState(() => _busyIds.remove(id));
    if (ok && success != null) showJwToast(context, success);
    if (!ok) showJwToast(context, l.friendsActionFailed, beadColor: context.jw.danger);
  }

  Future<bool> _remove(Friend f) async {
    final l = AppLocalizations.of(context);
    final ok = await showJwConfirm(
      context,
      title: l.friendsRemoveTitle(f.player.displayName),
      body: l.friendsRemoveBody,
      confirmLabel: l.friendsRemove,
      cancelLabel: l.commonCancel,
      destructive: true,
    );
    if (!ok || !mounted) return false;
    setState(() => _busyIds.add(f.userId));
    final removed = await ref.read(friendsProvider.notifier).remove(f);
    if (!mounted) return removed;
    setState(() => _busyIds.remove(f.userId));
    if (!removed) showJwToast(context, l.friendsActionFailed, beadColor: context.jw.danger);
    return removed;
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    // Also re-try the backend session: no session is the usual cause.
    unawaited(ref.read(sessionProvider.notifier).ensureBackendSession());
    await ref.read(friendsProvider.notifier).refresh();
    if (mounted) setState(() => _retrying = false);
  }
}
