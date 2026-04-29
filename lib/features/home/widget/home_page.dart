import 'package:dartx/dartx.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:gap/gap.dart';
import 'package:hiddify/core/app_info/app_info_provider.dart';
import 'package:hiddify/core/localization/translations.dart';
import 'package:hiddify/core/router/bottom_sheets/bottom_sheets_notifier.dart';
import 'package:hiddify/core/router/dialog/dialog_notifier.dart';
import 'package:hiddify/features/app_update/notifier/app_update_notifier.dart';
import 'package:hiddify/features/app_update/notifier/app_update_state.dart';
import 'package:hiddify/features/home/widget/connection_button.dart';
import 'package:hiddify/features/profile/notifier/active_profile_notifier.dart';
import 'package:hiddify/features/profile/widget/profile_tile.dart';
import 'package:hiddify/features/proxy/active/active_proxy_card.dart';
import 'package:hiddify/features/proxy/active/active_proxy_delay_indicator.dart';
import 'package:hiddify/gen/assets.gen.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:sliver_tools/sliver_tools.dart';

class HomePage extends HookConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final t = ref.watch(translationsProvider).requireValue;
    // final hasAnyProfile = ref.watch(hasAnyProfileProvider);
    final activeProfile = ref.watch(activeProfileProvider);

    // FreeCore: auto-check для обновлений при первом mount HomePage.
    // appUpdateNotifierProvider keepAlive — повторные mount'ы НЕ перезапускают
    // check() (state сохранён). Один запрос на сессию приложения, на About
    // page остаётся ручная кнопка "Проверить обновления" (мы её спрятали из
    // sidebar, но route жив для deep-links).
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final state = ref.read(appUpdateNotifierProvider);
        if (state is AppUpdateStateInitial) {
          ref.read(appUpdateNotifierProvider.notifier).check();
        }
      });
      return null;
    }, const []);

    // Если check() обнаружил новую версию — показать dialog. canIgnore=true
    // чтобы юзер мог отложить (на About это false — там он сам нажал).
    ref.listen<AppUpdateState>(appUpdateNotifierProvider, (_, next) async {
      if (!context.mounted) return;
      if (next is AppUpdateStateAvailable) {
        final appInfo = ref.read(appInfoProvider).requireValue;
        await ref.read(dialogNotifierProvider.notifier).showNewVersion(
              currentVersion: appInfo.presentVersion,
              newVersion: next.versionInfo,
              canIgnore: true,
            );
      }
    });

    return Scaffold(
      appBar: AppBar(
        // leading: (RootScaffold.stateKey.currentState?.hasDrawer ?? false) && showDrawerButton(context)
        //     ? DrawerButton(
        //         onPressed: () {
        //           RootScaffold.stateKey.currentState?.openDrawer();
        //         },
        //       )
        //     : null,
        title: Row(
          children: [
            Image.asset('assets/freecore/app_icon.png', height: 24, width: 24),
            const Gap(8),
            // FreeCore: только название без dev-метки версии — конечный
            // юзер не видит "1.0.0 dev" рядом с лого.
            Text(t.common.appTitle, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
        // FreeCore: убрали actions (filter+plus иконки) — для VPN-клиента
        // с одним профилем они не нужны. Quick-settings всё ещё доступны
        // через шестерёнку в Settings tab.
        actions: const [],
      ),
      // FreeCore: без world_map background — компактный однотонный фон
      // ближе к стилю HAPP. Меньше визуального шума, кнопка коннекта
      // становится центральной точкой внимания.
      body: Container(
        color: theme.scaffoldBackgroundColor,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 600, // Set the maximum width here
                ),
                child: CustomScrollView(
                  slivers: [
                    // switch (activeProfile) {
                    // AsyncData(value: final profile?) =>
                    MultiSliver(
                      children: [
                        // const Gap(100),
                        switch (activeProfile) {
                          AsyncData(value: final profile?) => ProfileTile(
                            profile: profile,
                            isMain: true,
                            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            color: Theme.of(context).colorScheme.surfaceContainer,
                          ),
                          _ => const Text(""),
                        },
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [ConnectionButton(), ActiveProxyDelayIndicator()],
                                ),
                              ),
                              ActiveProxyFooter(),
                            ],
                          ),
                        ),
                      ],
                    ),
                    // AsyncData() => switch (hasAnyProfile) {
                    //     AsyncData(value: true) => const EmptyActiveProfileHomeBody(),
                    //     _ => const EmptyProfilesHomeBody(),
                    //   },
                    // AsyncError(:final error) => SliverErrorBodyPlaceholder(t.presentShortError(error)),
                    // _ => const SliverToBoxAdapter(),
                    // },
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppVersionLabel extends HookConsumerWidget {
  const AppVersionLabel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(translationsProvider).requireValue;
    final theme = Theme.of(context);

    final version = ref.watch(appInfoProvider).requireValue.presentVersion;
    if (version.isBlank) return const SizedBox();

    return Semantics(
      label: t.common.version,
      button: false,
      child: Container(
        decoration: BoxDecoration(color: theme.colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(4)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          version,
          textDirection: TextDirection.ltr,
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSecondaryContainer),
        ),
      ),
    );
  }
}
