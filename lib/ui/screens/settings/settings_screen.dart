import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../../data/models/settings.dart';
import '../../../platform/analytics/analytics_service.dart';
import '../../../platform/display/display_service.dart';
import '../../../platform/store_listing/store_listing_service.dart';
import '../../../state/data_providers.dart';
import '../../../state/entitlement_providers.dart';
import '../../../state/platform_providers.dart';
import '../../../state/reminder_controller.dart';
import '../../../state/session_controller.dart';
import '../../../state/social_providers.dart';
import '../../../state/store_listing_controller.dart';
import '../../components/components.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../router.dart';
import '../../theme/jw_theme.dart';
import '../../theme/jw_tokens.dart';
import '../../widgets/widgets.dart';
import '../legal/legal_screen.dart';
import '../reminder/reminder_primer_sheet.dart';
import 'screen_chrome.dart';

/// Settings (screen 15): feedback, display, account and legal groups. Every change
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
    final display = ref.watch(displayServiceProvider);
    final rates = ref.watch(displayRatesProvider).value;
    final store = ref.watch(storeListingProvider);
    final update = ref.watch(appUpdateProvider);
    final haptic = ref.watch(hapticsProvider).selection;
    final notifications = ref.watch(notificationServiceProvider);
    final reminderPermitted = ref.watch(reminderPermissionProvider).value ?? false;
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
          JwEyebrow(l.settingsGroupFeedback, top: 18),
          JwListGroup(
            children: [
              JwListRow(
                icon: JwIcons.sound,
                badgeFill: JwFill.pink,
                title: l.settingsMusic,
                trailing: toggle(l.settingsMusic, s.music, (v) {
                  ref.read(audioProvider).setMusicEnabled(v);
                  change('music', (x) => x.copyWith(music: v));
                }),
              ),
              JwListRow(
                icon: JwIcons.sparkle,
                badgeFill: JwFill.pink,
                title: l.settingsSoundEffects,
                trailing: toggle(l.settingsSoundEffects, s.soundEffects, (v) {
                  ref.read(audioProvider).setSfxEnabled(v);
                  change('sound_effects', (x) => x.copyWith(soundEffects: v));
                }),
              ),
              JwListRow(
                icon: JwIcons.vib,
                badgeFill: JwFill.sky,
                title: l.settingsHaptics,
                trailing: toggle(l.settingsHaptics, s.haptics, (v) {
                  ref.read(hapticsProvider).setEnabled(v);
                  change('haptics', (x) => x.copyWith(haptics: v));
                }),
              ),
              // On only when the setting and the OS permission both are.
              // Switching it on without the permission opens the primer
              // first; only "Turn on reminders" asks the OS, "Not now"
              // leaves it off. Once the OS said no, it asks the OS directly
              // and points to the phone's settings.
              if (notifications.isSupported)
                JwListRow(
                  icon: JwIcons.cal,
                  badgeFill: JwFill.mint,
                  title: l.settingsDailyReminder,
                  trailing: toggle(l.settingsDailyReminder, s.dailyReminder && reminderPermitted, (v) async {
                    unawaited(ref.read(analyticsProvider).log(AnalyticsEvents.settingsChanged, {'setting': 'daily_reminder'}));
                    final reminders = ref.read(reminderControllerProvider);
                    if (v && await reminders.settingsNeedsPrimer()) {
                      if (!context.mounted) return;
                      final yes = await showReminderPrimer(context);
                      final result = await reminders.answerPrompt(accepted: yes, source: ReminderPromptSource.settings);
                      ref.invalidate(reminderPermissionProvider);
                      if (result == ReminderPromptResult.osDenied && context.mounted) {
                        showJwToast(context, l.settingsDailyReminderBlocked);
                      }
                      return;
                    }
                    final on = await reminders.setEnabled(v);
                    ref.invalidate(reminderPermissionProvider);
                    if (v && !on && context.mounted) showJwToast(context, l.settingsDailyReminderBlocked);
                  }),
                  below: _RowCaption(l.settingsDailyReminderHint),
                ),
            ],
          ),
          JwEyebrow(l.settingsGroupDisplay),
          JwListGroup(
            children: [
              JwListRow(
                icon: JwIcons.moon,
                badgeFill: JwFill.purple,
                title: l.settingsTheme,
                below: BadgeTabs<ThemePreference>(
                  inset: true,
                  tabs: {
                    ThemePreference.light: BadgeTab(label: l.settingsThemeLight, icon: JwIcons.sun, fill: JwFill.yellow),
                    ThemePreference.dark: BadgeTab(label: l.settingsThemeDark, icon: JwIcons.moon, fill: JwFill.purple),
                    ThemePreference.system: BadgeTab(label: l.settingsThemeSystem, icon: JwIcons.tile, fill: JwFill.sky),
                  },
                  selected: s.theme,
                  onHaptic: haptic,
                  onChanged: (v) => change('theme', (x) => x.copyWith(theme: v)),
                ),
              ),
              JwListRow(
                icon: JwIcons.clock,
                badgeFill: JwFill.yellow,
                title: l.settingsShowTimer,
                trailing: toggle(l.settingsShowTimer, s.showTimer, (v) => change('show_timer', (x) => x.copyWith(showTimer: v))),
              ),
              JwListRow(
                icon: JwIcons.text,
                badgeFill: JwFill.mint,
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
              // Android only (iOS keeps its own cadence), and only on a
              // screen that can go faster than 60 Hz.
              if (display.canControl && rates != null && rates.supportsHighRefresh)
                JwListRow(
                  icon: JwIcons.gauge,
                  badgeFill: JwFill.sky,
                  title: l.settingsHighRefresh,
                  trailing: toggle(l.settingsHighRefresh, s.highRefreshRate, (v) {
                    change('high_refresh_rate', (x) => x.copyWith(highRefreshRate: v));
                    // The display switches a moment after the request.
                    Future<void>.delayed(const Duration(milliseconds: 600), () => ref.invalidate(displayRatesProvider));
                  }),
                  below: _RefreshCaption(rates: rates, enabled: s.highRefreshRate),
                ),
              JwListRow(
                icon: JwIcons.motion,
                badgeFill: JwFill.coral,
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
                badgeFill: JwFill.purple,
                title: l.settingsAccount,
                value: accountValue,
                chevron: true,
                onHaptic: haptic,
                onTap: () => context.push(AppRoutes.account),
              ),
              JwListRow(
                icon: JwIcons.heart,
                badgeFill: JwFill.mint,
                title: l.settingsFriends,
                chevron: true,
                onHaptic: haptic,
                onTap: () => context.push(AppRoutes.friends),
              ),
              JwListRow(
                icon: JwIcons.bag,
                badgeFill: JwFill.yellow,
                title: l.settingsRemoveAds,
                value: adsRemoved ? l.storePurchased : removeAdsPrice,
                monoValue: !adsRemoved,
                chevron: true,
                onHaptic: haptic,
                onTap: () => context.push(AppRoutes.store),
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
          JwEyebrow(l.settingsGroupSupport),
          JwListGroup(
            children: [
              JwListRow(
                key: const ValueKey('settings-how-to-play'),
                icon: JwIcons.info,
                badgeFill: JwFill.sky,
                title: l.settingsHowToPlay,
                chevron: true,
                onHaptic: haptic,
                onTap: () => context.push(AppRoutes.howToPlay),
              ),
              JwListRow(
                icon: JwIcons.mail,
                badgeFill: JwFill.coral,
                title: l.settingsContactUs,
                chevron: true,
                onHaptic: haptic,
                onTap: () => openContactEmail(context, version: version),
              ),
              if (store.canOpenStoreListing)
                JwListRow(
                  icon: JwIcons.star,
                  badgeFill: JwFill.yellow,
                  title: l.settingsRateApp,
                  chevron: true,
                  onHaptic: haptic,
                  onTap: () async {
                    final ok = await store.openStoreListing();
                    if (!ok && context.mounted) showJwToast(context, l.settingsRateAppFailed);
                  },
                ),
              if (store.supportsUpdates)
                JwListRow(
                  icon: JwIcons.download,
                  badgeFill: JwFill.mint,
                  title: l.settingsUpdates,
                  value: switch (update) {
                    UpdateState.unknown => null,
                    UpdateState.upToDate => l.settingsUpdateUpToDate,
                    UpdateState.available => l.settingsUpdateAvailable,
                    UpdateState.downloading => l.settingsUpdateDownloading,
                    UpdateState.downloaded => l.settingsUpdateReady,
                  },
                  chevron: true,
                  onHaptic: haptic,
                  onTap: () async {
                    final r = await ref.read(appUpdateProvider.notifier).checkFromSettings();
                    if (!context.mounted) return;
                    final msg = switch (r) {
                      ManualUpdateResult.upToDate => l.settingsUpdateLatestToast,
                      ManualUpdateResult.unavailable => l.settingsUpdateUnavailableToast,
                      ManualUpdateResult.started when ref.read(appUpdateProvider) == UpdateState.downloading =>
                        l.settingsUpdateDownloadingToast,
                      ManualUpdateResult.started || ManualUpdateResult.declined => null,
                    };
                    if (msg != null) showJwToast(context, msg);
                  },
                ),
            ],
          ),
          JwEyebrow(l.settingsGroupLegal),
          JwListGroup(
            children: [
              JwListRow(
                icon: JwIcons.shield,
                badgeFill: JwFill.sky,
                title: l.legalPrivacy,
                chevron: true,
                onHaptic: haptic,
                onTap: () => context.push(AppRoutes.legal(LegalDoc.privacy)),
              ),
              JwListRow(
                icon: JwIcons.text,
                badgeFill: JwFill.purple,
                title: l.legalTerms,
                chevron: true,
                onHaptic: haptic,
                onTap: () => context.push(AppRoutes.legal(LegalDoc.terms)),
              ),
              JwListRow(
                icon: JwIcons.bag,
                badgeFill: JwFill.yellow,
                title: l.legalRefund,
                chevron: true,
                onHaptic: haptic,
                onTap: () => context.push(AppRoutes.legal(LegalDoc.refund)),
              ),
              // UMP decides whether a privacy options entry point is required
              // (e.g. EEA/UK); elsewhere the row would open nothing.
              if (ads.privacyOptionsRequired)
                JwListRow(
                  icon: JwIcons.eye,
                  badgeFill: JwFill.sky,
                  title: l.settingsAdPrivacy,
                  chevron: true,
                  onHaptic: haptic,
                  onTap: () => unawaited(ads.showPrivacyOptions()),
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
            const Center(child: IconBadge(icon: JwIcons.text, fill: JwFill.mint, size: 60)),
            const SizedBox(height: 14),
            Text(l.settingsTileSize, style: jw.text.h3.copyWith(fontSize: 21), textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(l.settingsTileSizeHint, style: jw.text.body.copyWith(color: jw.textMuted), textAlign: TextAlign.center),
            const SizedBox(height: 18),
            JwListGroup(
              children: [
                for (final t in TileSizePreference.values)
                  JwListRow(
                    title: _tileSizeLabel(l, t),
                    semanticLabel: _tileSizeLabel(l, t),
                    trailing: t == current ? const IconBadge(icon: JwIcons.check, fill: JwFill.mint, size: 26) : null,
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

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final l = AppLocalizations.of(context);
    final ok = await showJwConfirm(
      context,
      title: l.resetTitle,
      body: l.resetBody,
      confirmLabel: l.resetConfirm,
      cancelLabel: l.commonCancel,
      destructive: true,
      leading: JwIconWell(icon: JwIcons.trash, color: context.jw.danger, size: 64),
    );
    if (!ok) return;
    await ref.read(progressRepositoryProvider).resetAll();
    unawaited(ref.read(analyticsProvider).log(AnalyticsEvents.settingsChanged, {'setting': 'reset_progress'}));
    if (context.mounted) showJwToast(context, l.resetDone);
  }
}

/// Under the High refresh rate toggle: what the screen can do, what it is
/// doing, and battery saver when it holds the rate down.
class _RefreshCaption extends StatelessWidget {
  const _RefreshCaption({required this.rates, required this.enabled});

  final DisplayRates rates;
  final bool enabled;

  static String _hz(double v) => v.round().toString();

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final text = [
      l.settingsHighRefreshHint(_hz(rates.max)),
      if (enabled && rates.current > 0) l.settingsHighRefreshNow(_hz(rates.current)),
      if (enabled && rates.lowPower) l.settingsHighRefreshBatterySaver,
    ].join(' ');
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Text(text, style: jw.text.callout.copyWith(fontSize: 14, fontWeight: FontWeight.w400, color: jw.textMuted)),
    );
  }
}

/// A muted line under a settings row, aligned with its title.
class _RowCaption extends StatelessWidget {
  const _RowCaption(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Text(text, style: jw.text.callout.copyWith(fontSize: 14, fontWeight: FontWeight.w400, color: jw.textMuted)),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({required this.version});

  final String? version;

  @override
  Widget build(BuildContext context) {
    final jw = context.jw;
    final l = AppLocalizations.of(context);
    final muted = jw.text.callout.copyWith(fontSize: 14.5, fontWeight: FontWeight.w400, color: jw.textMuted);
    final version = this.version;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: '${l.appName} '),
          if (version != null) TextSpan(text: version, style: jw.text.numM.copyWith(fontSize: 14.5, color: jw.textMuted)),
          const TextSpan(text: ' · pranta.dev'),
        ],
      ),
      style: muted,
      textAlign: TextAlign.center,
    );
  }
}
