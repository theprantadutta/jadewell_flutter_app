import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/models/settings.dart';
import '../../../platform/analytics/analytics_service.dart';
import '../../../state/data_providers.dart';
import '../../../state/entitlement_providers.dart';
import '../../../state/platform_providers.dart';
import '../../../state/session_controller.dart';
import '../../../state/social_providers.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../router.dart';
import '../../theme/clay.dart';
import '../../theme/jw_theme.dart';
import '../../widgets/widgets.dart';
import 'screen_chrome.dart';

/// Privacy policy (opened in the browser once url_launcher is added).
const kPrivacyPolicyUrl = 'https://jadewell.pranta.dev/privacy';

/// Settings (screen 15): feedback, display and account groups. Every change
/// persists through [SettingsController.change] and logs `settings_changed`
/// with the setting's name only.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final s = ref.watch(settingsProvider).value ?? const AppSettings();
    final session = ref.watch(sessionProvider).value;
    // The entitlement is the truth; the ad service's flag mirrors it.
    final adsRemoved = ref.watch(entitlementProvider).removeAds || ref.watch(adServiceProvider).adsRemoved;
    final removeAdsPrice = ref.watch(removeAdsPriceProvider); // null while the store has nothing to sell
    final ads = ref.watch(adServiceProvider);
    final version = ref.watch(appVersionProvider).value;
    final haptic = ref.watch(hapticsProvider).selection;
    final jw = context.jw;

    void change(String name, AppSettings Function(AppSettings) edit) {
      unawaited(ref.read(settingsProvider.notifier).change(edit));
      unawaited(ref.read(analyticsProvider).log(AnalyticsEvents.settingsChanged, {'setting': name}));
    }

    Widget toggle(String label, bool value, ValueChanged<bool> onChanged) => JwToggle(
          value: value,
          onChanged: onChanged,
          onHaptic: haptic,
          semanticLabel: label,
        );

    final identity = session?.identity;
    final accountValue = switch (identity) {
      null => l.accountGuest,
      final i when i.isAnonymous => l.accountGuest,
      final i when i.providers.contains('google.com') => l.accountProviderGoogle,
      final i when i.providers.contains('apple.com') => l.accountProviderApple,
      final i => i.email ?? l.accountProviderEmail,
    };

    return JwPage(
      title: l.settingsTitle,
      onHaptic: haptic,
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          JwEyebrow(l.settingsGroupFeedback, top: 22),
          JwListGroup(
            children: [
              JwListRow(
                icon: JwIcons.sound,
                title: l.settingsMusic,
                trailing: toggle(l.settingsMusic, s.music, (v) {
                  ref.read(audioProvider).setMusicEnabled(v);
                  change('music', (x) => x.copyWith(music: v));
                }),
              ),
              JwListRow(
                icon: JwIcons.sparkle,
                title: l.settingsSoundEffects,
                trailing: toggle(l.settingsSoundEffects, s.soundEffects, (v) {
                  ref.read(audioProvider).setSfxEnabled(v);
                  change('sound_effects', (x) => x.copyWith(soundEffects: v));
                }),
              ),
              JwListRow(
                icon: JwIcons.vib,
                title: l.settingsHaptics,
                trailing: toggle(l.settingsHaptics, s.haptics, (v) {
                  ref.read(hapticsProvider).setEnabled(v);
                  change('haptics', (x) => x.copyWith(haptics: v));
                }),
              ),
            ],
          ),
          JwEyebrow(l.settingsGroupDisplay),
          JwListGroup(
            children: [
              JwListRow(
                icon: JwIcons.moon,
                title: l.settingsTheme,
                below: JwSegmented<ThemePreference>(
                  segments: {
                    ThemePreference.light: l.settingsThemeLight,
                    ThemePreference.dark: l.settingsThemeDark,
                    ThemePreference.system: l.settingsThemeSystem,
                  },
                  selected: s.theme,
                  onHaptic: haptic,
                  onChanged: (v) => change('theme', (x) => x.copyWith(theme: v)),
                ),
              ),
              JwListRow(
                icon: JwIcons.clock,
                title: l.settingsShowTimer,
                trailing: toggle(l.settingsShowTimer, s.showTimer, (v) => change('show_timer', (x) => x.copyWith(showTimer: v))),
              ),
              JwListRow(
                icon: JwIcons.text,
                title: l.settingsTileSize,
                value: _tileSizeLabel(l, s.tileSize),
                chevron: true,
                onHaptic: haptic,
                onTap: () async {
                  final picked = await _pickTileSize(context, s.tileSize, haptic);
                  if (picked != null && picked != s.tileSize) {
                    change('tile_size', (x) => x.copyWith(tileSize: picked));
                  }
                },
              ),
              JwListRow(
                icon: JwIcons.motion,
                title: l.settingsReduceMotion,
                trailing: toggle(
                  l.settingsReduceMotion,
                  s.reduceMotion,
                  (v) => change('reduce_motion', (x) => x.copyWith(reduceMotion: v)),
                ),
              ),
            ],
          ),
          JwEyebrow(l.settingsGroupAccount),
          JwListGroup(
            children: [
              JwListRow(
                icon: JwIcons.user,
                title: l.settingsAccount,
                value: accountValue,
                chevron: true,
                onHaptic: haptic,
                onTap: () => context.push(AppRoutes.account),
              ),
              JwListRow(
                icon: JwIcons.heart,
                title: l.settingsFriends,
                chevron: true,
                onHaptic: haptic,
                onTap: () => context.push(AppRoutes.friends),
              ),
              JwListRow(
                icon: JwIcons.bag,
                title: l.settingsRemoveAds,
                value: adsRemoved ? l.storePurchased : removeAdsPrice,
                monoValue: !adsRemoved,
                chevron: true,
                onHaptic: haptic,
                onTap: () => context.push(AppRoutes.store),
              ),
              JwListRow(
                icon: JwIcons.shield,
                title: l.settingsPrivacy,
                chevron: true,
                onHaptic: haptic,
                onTap: () => _openPrivacy(context),
              ),
              // UMP decides whether a privacy options entry point is required
              // (e.g. EEA/UK); elsewhere the row would open nothing.
              if (ads.privacyOptionsRequired)
                JwListRow(
                  icon: JwIcons.eye,
                  title: l.settingsAdPrivacy,
                  chevron: true,
                  onHaptic: haptic,
                  onTap: () => unawaited(ads.showPrivacyOptions()),
                ),
              JwListRow(
                icon: JwIcons.trash,
                title: l.settingsResetProgress,
                destructive: true,
                onHaptic: haptic,
                onTap: () => _confirmReset(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 26),
          _Footer(version: version),
          SizedBox(height: jw.space.s2),
        ],
      ),
    );
  }

  static String _tileSizeLabel(AppLocalizations l, TileSizePreference t) => switch (t) {
        TileSizePreference.small => l.settingsTileSizeSmall,
        TileSizePreference.medium => l.settingsTileSizeMedium,
        TileSizePreference.large => l.settingsTileSizeLarge,
      };

  Future<TileSizePreference?> _pickTileSize(BuildContext context, TileSizePreference current, VoidCallback haptic) {
    final l = AppLocalizations.of(context);
    return showJwSheet<TileSizePreference>(
      context,
      semanticLabel: l.settingsTileSize,
      builder: (ctx) {
        final jw = ctx.jw;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.settingsTileSize, style: jw.text.h3, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(l.settingsTileSizeHint, style: jw.text.body.copyWith(color: jw.textMuted), textAlign: TextAlign.center),
            const SizedBox(height: 18),
            JwListGroup(
              children: [
                for (final t in TileSizePreference.values)
                  JwListRow(
                    title: _tileSizeLabel(l, t),
                    semanticLabel: _tileSizeLabel(l, t),
                    trailing: t == current ? JwIcon(JwIcons.check, size: 20, color: jw.accent) : null,
                    onHaptic: haptic,
                    onTap: () => Navigator.of(ctx).pop(t),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  /// Opens the policy in the browser; falls back to a sheet with the URL.
  Future<void> _openPrivacy(BuildContext context) async {
    var opened = false;
    try {
      opened = await launchUrl(Uri.parse(kPrivacyPolicyUrl), mode: LaunchMode.externalApplication);
    } on Object {
      opened = false;
    }
    if (!opened && context.mounted) await _showPrivacy(context);
  }

  Future<void> _showPrivacy(BuildContext context) {
    final l = AppLocalizations.of(context);
    return showJwSheet<void>(
      context,
      semanticLabel: l.privacyTitle,
      builder: (ctx) {
        final jw = ctx.jw;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(l.privacyTitle, style: jw.text.h3, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(l.privacyBody, style: jw.text.body.copyWith(color: jw.textMuted), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            DecoratedBox(
              decoration: jw.clay(ClayLevel.sunken, radius: 18),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: SelectableText(
                  kPrivacyPolicyUrl,
                  textAlign: TextAlign.center,
                  style: jw.text.numM.copyWith(fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 18),
            JwButton.primary(
              label: l.commonCopyLink,
              icon: JwIcons.check,
              expand: true,
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: kPrivacyPolicyUrl));
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop();
                showJwToast(context, l.commonLinkCopied);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final ok = await showJwConfirm(
      context,
      title: l.resetTitle,
      body: l.resetBody,
      confirmLabel: l.resetConfirm,
      cancelLabel: l.commonCancel,
      destructive: true,
    );
    if (!ok) return;
    await ref.read(progressRepositoryProvider).resetAll();
    unawaited(ref.read(analyticsProvider).log(AnalyticsEvents.settingsChanged, {'setting': 'reset_progress'}));
    if (context.mounted) showJwToast(context, l.resetDone);
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.version});

  final String? version;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final muted = jw.text.callout.copyWith(fontSize: 14.5, fontWeight: FontWeight.w400, color: jw.textMuted);
    return Center(
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '${AppLocalizations.of(context).appName} '),
            if (version != null) TextSpan(text: version, style: jw.text.numM.copyWith(fontSize: 14.5, color: jw.textMuted)),
            const TextSpan(text: ' · pranta.dev'),
          ],
        ),
        style: muted,
      ),
    );
  }
}
