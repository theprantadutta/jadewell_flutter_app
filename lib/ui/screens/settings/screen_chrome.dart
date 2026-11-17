import 'dart:async';

import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../components/pop_background.dart';
import '../../router.dart';
import '../../theme/clay.dart';
import '../../theme/jw_background.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/widgets.dart';

// Shared chrome for the settings / store / account / friends / leaderboard
// screens: page frame with the round back button, eyebrow headings, clay
// text field, sheet / dialog / toast presentation and small formatters.

/// Blobs of the meta screens (12–17): purple top-right, yellow and mint on
/// the left edge, pink bottom-right, as in the reference screens.
const kMetaBlobs = PopBlobs.board;

/// Screen frame: background with orbs, safe area, 46 pt back (or close)
/// button with a 32/700 title and optional subtitle, then [child].
class JwPage extends StatelessWidget {
  const JwPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.close = false,
    this.trailing,
    this.onBack,
    this.onHaptic,
  });

  final String? title;
  final String? subtitle;
  final Widget child;

  /// Close (×) instead of back (modal-style screens such as the store).
  final bool close;
  final Widget? trailing;
  final VoidCallback? onBack;
  final VoidCallback? onHaptic;

  static void defaultBack(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = MaterialLocalizations.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: jw.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: jw.surface,
        body: JwBackground(
          blobs: kMetaBlobs,
          child: DefaultTextStyle(
            style: jw.text.body,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      children: [
                        JwIconButton(
                          icon: close ? JwIcons.x : JwIcons.back,
                          semanticLabel: close ? l.closeButtonTooltip : l.backButtonTooltip,
                          onHaptic: onHaptic,
                          onPressed: onBack ?? () => defaultBack(context),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: title == null
                              ? const SizedBox.shrink()
                              : Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Semantics(
                                      header: true,
                                      child: Text(
                                        title!,
                                        style: jw.text.h1.copyWith(fontSize: subtitle == null ? 28 : 26, height: 1.15),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (subtitle != null)
                                      Text(
                                        subtitle!,
                                        style: jw.text.body.copyWith(fontSize: 15.5, color: jw.textMuted),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                        ),
                        ?trailing,
                      ],
                    ),
                  ),
                  Expanded(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Group label in eyebrow style, 22 pt from the edge as in the design.
class JwEyebrow extends StatelessWidget {
  const JwEyebrow(this.text, {super.key, this.top = 26});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(8, top, 8, 12),
        child: Semantics(header: true, child: Text(text.toUpperCase(), style: context.jw.text.eyebrow.copyWith(fontSize: 13))),
      );
}

/// Sunken clay text field (e0 well, radius 18, 52 tall).
class JwTextField extends StatelessWidget {
  const JwTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.label,
    this.obscure = false,
    this.mono = false,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.autofillHints,
    this.inputFormatters,
    this.onChanged,
    this.onSubmitted,
    this.textInputAction,
    this.autofocus = false,
    this.errorText,
    this.maxLength,
    this.trailing,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String hint;
  final String? label;
  final bool obscure;
  final bool mono;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final Iterable<String>? autofillHints;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextInputAction? textInputAction;
  final bool autofocus;
  final String? errorText;
  final int? maxLength;
  final Widget? trailing;

  /// False shows the value read-only (e.g. a locked username).
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final style = mono
        ? jw.text.numM.copyWith(fontSize: 18, letterSpacing: 1.2)
        : jw.text.body.copyWith(fontSize: 16.5);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 6),
            child: Text(label!, style: jw.text.callout.copyWith(color: jw.textMuted)),
          ),
        DecoratedBox(
          decoration: jw.clay(ClayLevel.sunken, radius: 18),
          child: SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: controller,
                      enabled: enabled,
                      obscureText: obscure,
                      keyboardType: keyboardType,
                      textCapitalization: textCapitalization,
                      autofillHints: autofillHints,
                      inputFormatters: inputFormatters,
                      onChanged: onChanged,
                      onSubmitted: onSubmitted,
                      textInputAction: textInputAction,
                      autofocus: autofocus,
                      autocorrect: false,
                      enableSuggestions: !obscure,
                      maxLength: maxLength,
                      cursorColor: jw.accent,
                      style: style,
                      decoration: InputDecoration.collapsed(
                        hintText: hint,
                        hintStyle: style.copyWith(color: jw.textMuted.withValues(alpha: 0.7)),
                      ).copyWith(counterText: ''),
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: JwMotion.quick,
          child: errorText == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(left: 6, top: 6),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(errorText!, style: jw.text.caption.copyWith(color: jw.danger, fontSize: 13.5)),
                  ),
                ),
        ),
      ],
    );
  }
}

/// A friendly card for offline / not-available-yet states, with a retry.
class JwNoticeCard extends StatelessWidget {
  const JwNoticeCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.busy = false,
    this.onHaptic,
  });

  final String icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool busy;
  final VoidCallback? onHaptic;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return DecoratedBox(
      decoration: jw.clay(ClayLevel.raised, radius: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                JwIconWell(icon: icon),
                const SizedBox(width: 14),
                Expanded(child: Text(title, style: jw.text.h3.copyWith(fontSize: 17.5))),
              ],
            ),
            const SizedBox(height: 10),
            Text(body, style: jw.text.body.copyWith(color: jw.textMuted)),
            if (actionLabel != null) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: JwButton.secondary(
                  label: actionLabel!,
                  icon: JwIcons.replay,
                  small: true,
                  onHaptic: onHaptic,
                  onPressed: busy ? null : onAction,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A primary/secondary button that shows a small spinner while [busy].
class JwBusyButton extends StatelessWidget {
  const JwBusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.variant = JwButtonVariant.primary,
    this.icon,
    this.small = false,
    this.onHaptic,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final JwButtonVariant variant;
  final String? icon;
  final bool small;
  final VoidCallback? onHaptic;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final button = JwButton(
      label: label,
      variant: variant,
      icon: busy ? null : icon,
      small: small,
      expand: true,
      onHaptic: onHaptic,
      onPressed: busy ? null : onPressed,
    );
    if (!busy) return button;
    final color = variant == JwButtonVariant.primary ? jw.onAccent : jw.textPrimary;
    return Stack(
      alignment: Alignment.centerLeft,
      children: [
        button,
        Positioned(
          left: 22,
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: color),
          ),
        ),
      ],
    );
  }
}

// ---- presentation ----

/// Shows [child] in a clay sheet: scrim fades in, the sheet rises 400 ms
/// springSoft (MOTION_SPEC §4); follows the keyboard.
Future<T?> showJwSheet<T>(BuildContext context, {required WidgetBuilder builder, String? semanticLabel}) {
  final jw = context.jw;
  final reduce = JwReduceMotion.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: JwBase.transparent,
    elevation: 0,
    barrierColor: jw.scrim,
    showDragHandle: false,
    sheetAnimationStyle: reduce
        ? const AnimationStyle(duration: Duration(milliseconds: 150), reverseDuration: Duration(milliseconds: 150))
        : const AnimationStyle(
            duration: JwMotion.gentle,
            reverseDuration: Duration(milliseconds: 250),
            curve: JwMotion.easeOutSoft,
            reverseCurve: JwMotion.exit,
          ),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: JwSheet(semanticLabel: semanticLabel, child: Builder(builder: builder)),
        ),
      ),
    ),
  );
}

/// Centred clay dialog with a fading scrim; [builder] returns a [JwDialog].
Future<T?> showJwDialog<T>(BuildContext context, {required WidgetBuilder builder}) {
  final jw = context.jw;
  final reduce = JwReduceMotion.of(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: jw.scrim,
    transitionDuration: reduce ? const Duration(milliseconds: 150) : JwMotion.base,
    pageBuilder: (ctx, _, _) => Center(
      child: Material(type: MaterialType.transparency, child: Builder(builder: builder)),
    ),
    transitionBuilder: (ctx, a, _, child) {
      final fade = CurvedAnimation(parent: a, curve: JwMotion.standard);
      if (reduce) return FadeTransition(opacity: fade, child: child);
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: Tween(begin: 0.94, end: 1.0).animate(CurvedAnimation(parent: a, curve: JwMotion.easeOutSoft)),
          child: child,
        ),
      );
    },
  );
}

/// Yes/no confirmation; resolves true only when [confirmLabel] is tapped.
Future<bool> showJwConfirm(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
  required String cancelLabel,
  bool destructive = false,
}) async {
  final result = await showJwDialog<bool>(
    context,
    builder: (ctx) {
      final jw = ctx.jw;
      return JwDialog(
        title: title,
        body: body,
        actions: [
          JwButton.secondary(
            label: cancelLabel,
            small: true,
            expand: true,
            onPressed: () => Navigator.of(ctx).pop(false),
          ),
          if (destructive)
            ClayPressable(
              decoration: jw.clay(ClayLevel.primary, color: jw.danger),
              pressedDecoration: jw.clay(ClayLevel.pressed, color: jw.danger),
              onTap: () => Navigator.of(ctx).pop(true),
              semanticLabel: confirmLabel,
              height: 42,
              child: Center(
                child: Text(confirmLabel, style: jw.text.button.copyWith(color: jw.onAccent, fontSize: 15.5)),
              ),
            )
          else
            JwButton.primary(
              label: confirmLabel,
              small: true,
              expand: true,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
        ],
      );
    },
  );
  return result ?? false;
}

OverlayEntry? _toastEntry;

/// A clay toast above the bottom safe area for ~2.4 s.
void showJwToast(BuildContext context, String message, {Color? beadColor}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _toastEntry?.remove();
  late OverlayEntry entry;
  final theme = Theme.of(context);
  entry = OverlayEntry(
    builder: (_) => Theme(
      data: theme,
      child: _ToastHost(
        message: message,
        beadColor: beadColor,
        onDone: () {
          if (_toastEntry == entry) _toastEntry = null;
          if (entry.mounted) entry.remove();
        },
      ),
    ),
  );
  _toastEntry = entry;
  overlay.insert(entry);
}

class _ToastHost extends StatefulWidget {
  const _ToastHost({required this.message, required this.onDone, this.beadColor});

  final String message;
  final Color? beadColor;
  final VoidCallback onDone;

  @override
  State<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends State<_ToastHost> {
  bool _visible = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
    _timer = Timer(const Duration(milliseconds: 2400), () {
      if (!mounted) return;
      setState(() => _visible = false);
      _timer = Timer(JwMotion.base, widget.onDone);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = JwReduceMotion.of(context);
    final bottom = MediaQuery.paddingOf(context).bottom + 28;
    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: IgnorePointer(
        child: AnimatedSlide(
          offset: _visible || reduce ? Offset.zero : const Offset(0, 0.4),
          duration: JwMotion.base,
          curve: JwMotion.easeOutSoft,
          child: AnimatedOpacity(
            opacity: _visible ? 1 : 0,
            duration: reduce ? const Duration(milliseconds: 150) : JwMotion.quick,
            child: Center(
              child: DefaultTextStyle(
                style: context.jw.text.callout,
                // Long names shrink rather than overflow the 40 pt pill.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: JwToast(message: widget.message, beadColor: widget.beadColor),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---- formatting ----

/// `m:ss` (or `h:mm:ss` past an hour), for leaderboard times.
String formatClock(int ms) {
  final total = ms ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '$m:$ss';
}

/// Parses `#RRGGBB`; null when absent or malformed.
Color? parseHexColor(String? hex) => JwBase.fromHex(hex);

/// The Clay Pop fill closest in hue to a profile colour (the backend
/// stores a saturated `#RRGGBB`), so avatars always wear one of the six
/// fills; greys and missing colours fall back to the fill for [name].
JwFill avatarFill(String? hex, String name) {
  final c = parseHexColor(hex);
  if (c == null) return JwAvatar.fillFor(name);
  final hsv = HSVColor.fromColor(c);
  if (hsv.saturation < 0.15) return JwAvatar.fillFor(name);
  double dist(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  JwFill best = JwFill.purple;
  var bestD = double.infinity;
  for (final f in JwFill.all) {
    final d = dist(hsv.hue, HSVColor.fromColor(f.mid).hue);
    if (d < bestD) {
      bestD = d;
      best = f;
    }
  }
  return best;
}

/// The pastel avatar fill for a profile colour (the backend stores
/// saturated colours; avatars show them softened, as in the design).
Color? avatarPastel(String? hex, JwTheme jw) {
  final c = parseHexColor(hex);
  if (c == null) return null;
  return JwFaceInks.lighten(c, jw.isDark ? 0.42 : 0.58);
}
