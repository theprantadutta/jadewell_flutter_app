import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/widgets.dart';
import 'game_widgets.dart';

/// What the player chose on the pause card (screen 08).
enum PauseAction { resume, restart, settings, quit }

/// Paused card: eyebrow, the frozen time, layout meta, Resume, Restart,
/// Settings and Quit to collection.
class PausedCard extends StatelessWidget {
  const PausedCard({super.key, required this.time, required this.meta});

  final String time;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    void pop(PauseAction a) => Navigator.of(context).pop(a);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: DecoratedBox(
        decoration: jw.clay(ClayLevel.floating, radius: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l.gamePausedEyebrow.toUpperCase(), textAlign: TextAlign.center, style: jw.text.eyebrow),
              const SizedBox(height: 10),
              Text(time, textAlign: TextAlign.center, style: jw.text.numXl.copyWith(fontSize: 60, height: 1.1)),
              const SizedBox(height: 8),
              Text(meta, textAlign: TextAlign.center, style: jw.text.callout.copyWith(fontWeight: FontWeight.w400)),
              const SizedBox(height: 24),
              JwButton.primary(
                label: l.gamePausedResume,
                icon: JwIcons.play,
                expand: true,
                onPressed: () => pop(PauseAction.resume),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: JwButton.secondary(
                      label: l.gamePausedRestart,
                      icon: JwIcons.replay,
                      small: true,
                      expand: true,
                      onPressed: () => pop(PauseAction.restart),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: JwButton.secondary(
                      label: l.gamePausedSettings,
                      icon: JwIcons.gear,
                      small: true,
                      expand: true,
                      onPressed: () => pop(PauseAction.settings),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              JwButton.tertiary(label: l.gamePausedQuit, icon: JwIcons.door, onPressed: () => pop(PauseAction.quit)),
            ],
          ),
        ),
      ),
    );
  }
}

/// What the player chose on the "No moves" sheet (screen 07).
enum NoMovesAction { shuffle, undo, restart }

class NoMovesSheet extends StatelessWidget {
  const NoMovesSheet({super.key, required this.tilesLeft, required this.canUndo});

  final int tilesLeft;
  final bool canUndo;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    void pop(NoMovesAction a) => Navigator.of(context).pop(a);
    return JwSheet(
      semanticLabel: l.gameNoMovesTitle,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              const GameIconWell(icon: JwIcons.shuffle),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.gameNoMovesTitle, style: jw.text.h3.copyWith(fontSize: 21)),
                    const SizedBox(height: 4),
                    Text(l.gameNoMovesMeta(tilesLeft), style: jw.text.callout.copyWith(fontWeight: FontWeight.w400, color: jw.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(l.gameNoMovesBody, style: jw.text.body.copyWith(color: jw.textMuted)),
          const SizedBox(height: 22),
          JwButton.primary(
            label: l.gameNoMovesShuffle,
            icon: JwIcons.shuffle,
            expand: true,
            onPressed: () => pop(NoMovesAction.shuffle),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: JwButton.secondary(
                  label: l.gameNoMovesUndo,
                  icon: JwIcons.undo,
                  expand: true,
                  onPressed: canUndo ? () => pop(NoMovesAction.undo) : null,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: JwButton.secondary(
                  label: l.gameNoMovesRestart,
                  icon: JwIcons.replay,
                  expand: true,
                  onPressed: () => pop(NoMovesAction.restart),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shuffle confirmation (screen 09): icon well, title, body, the free
/// shuffles chip, Cancel / Shuffle. Pops `true` to shuffle.
class ShuffleConfirmDialog extends StatelessWidget {
  const ShuffleConfirmDialog({super.key, required this.tilesLeft, required this.freeLeft});

  final int tilesLeft;
  final int freeLeft;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    return Semantics(
      container: true,
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: l.gameShuffleTitle,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: DecoratedBox(
          decoration: jw.clay(ClayLevel.floating, radius: 32),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 26, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: GameIconWell(icon: JwIcons.shuffle, size: 66)),
                const SizedBox(height: 22),
                Text(l.gameShuffleTitle, textAlign: TextAlign.center, style: jw.text.h3.copyWith(fontSize: 21)),
                const SizedBox(height: 10),
                Text(l.gameShuffleBody(tilesLeft), textAlign: TextAlign.center, style: jw.text.body.copyWith(color: jw.textMuted)),
                const SizedBox(height: 18),
                Center(child: JwChip(value: '$freeLeft', label: l.gameShuffleFreeLeft)),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: JwButton.secondary(label: l.commonCancel, expand: true, onPressed: () => Navigator.of(context).pop(false)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: JwButton.primary(label: l.gameShuffleConfirm, expand: true, onPressed: () => Navigator.of(context).pop(true)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Watch a short video for another hint/shuffle?" (rewarded offer). Shows a
/// loading state while the ad plays; pops `true` when the reward was granted,
/// `false` when the video did not reward, and null for "Not now".
class RewardOfferSheet extends StatefulWidget {
  const RewardOfferSheet({super.key, required this.title, required this.body, required this.watch});

  final String title;
  final String body;

  /// Plays the ad and applies the reward; resolves to whether it was granted.
  final Future<bool> Function() watch;

  @override
  State<RewardOfferSheet> createState() => _RewardOfferSheetState();
}

class _RewardOfferSheetState extends State<RewardOfferSheet> {
  bool _loading = false;

  Future<void> _watch() async {
    setState(() => _loading = true);
    final ok = await widget.watch();
    if (mounted) Navigator.of(context).pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    return PopScope(
      canPop: !_loading,
      child: JwSheet(
        semanticLabel: widget.title,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Row(
              children: [
                const GameIconWell(icon: JwIcons.video),
                const SizedBox(width: 16),
                Expanded(child: Text(widget.title, style: jw.text.h3.copyWith(fontSize: 21))),
              ],
            ),
            const SizedBox(height: 16),
            Text(widget.body, style: jw.text.body.copyWith(color: jw.textMuted)),
            const SizedBox(height: 22),
            AnimatedSwitcher(
              duration: JwMotion.quick,
              child: _loading
                  ? SizedBox(
                      key: const ValueKey('loading'),
                      height: 56,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: jw.accent),
                          ),
                          const SizedBox(width: 12),
                          Text(l.gameRewardLoading, style: jw.text.button.copyWith(color: jw.textMuted)),
                        ],
                      ),
                    )
                  : JwButton.primary(
                      key: const ValueKey('watch'),
                      label: l.gameRewardWatch,
                      icon: JwIcons.video,
                      expand: true,
                      onPressed: _watch,
                    ),
            ),
            const SizedBox(height: 6),
            JwButton.tertiary(
              label: l.gameRewardNotNow,
              onPressed: _loading ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Back / predictive back: "Leave this board?" (the board is saved).
class QuitDialog extends StatelessWidget {
  const QuitDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return JwDialog(
      title: l.gameQuitTitle,
      body: l.gameQuitBody,
      actions: [
        JwButton.secondary(label: l.gameQuitStay, expand: true, onPressed: () => Navigator.of(context).pop(false)),
        JwButton.primary(label: l.gameQuitLeave, expand: true, onPressed: () => Navigator.of(context).pop(true)),
      ],
    );
  }
}

/// Intro for a rewarded interstitial (Google policy): states the reward, a
/// 5 s countdown, and Skip. Pops true only if the ad paid out.
class RewardedIntroSheet extends StatefulWidget {
  const RewardedIntroSheet({super.key, required this.title, required this.body, required this.icon, required this.watch});

  final String title;
  final String body;
  final String icon;
  final Future<bool> Function() watch;

  @override
  State<RewardedIntroSheet> createState() => _RewardedIntroSheetState();
}

class _RewardedIntroSheetState extends State<RewardedIntroSheet> {
  static const _countdown = 5;
  int _left = _countdown;
  Timer? _timer;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_left <= 1) {
        t.cancel();
        unawaited(_watch());
      } else {
        setState(() => _left--);
      }
    });
  }

  Future<void> _watch() async {
    if (_loading) return;
    _timer?.cancel();
    setState(() => _loading = true);
    final ok = await widget.watch();
    if (mounted) Navigator.of(context).pop(ok);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    return JwSheet(
      semanticLabel: widget.title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Row(
            children: [
              GameIconWell(icon: widget.icon, size: 56),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title, style: jw.text.h3.copyWith(fontSize: 20)),
                    const SizedBox(height: 4),
                    Text(widget.body, style: jw.text.callout.copyWith(fontWeight: FontWeight.w400, color: jw.textMuted)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: JwButton.secondary(
                  label: l.clearedHeadStartSkip,
                  expand: true,
                  onPressed: _loading ? null : () => Navigator.of(context).pop(false),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _loading
                    ? SizedBox(
                        height: 56,
                        child: Center(
                          child: SizedBox.square(
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: jw.accent),
                          ),
                        ),
                      )
                    : JwButton.primary(
                        label: '${l.clearedHeadStartWatch} · $_left',
                        icon: JwIcons.video,
                        expand: true,
                        semanticLabel: '${l.clearedHeadStartWatch}, ${l.clearedHeadStartCountdown(_left)}',
                        onPressed: _watch,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
