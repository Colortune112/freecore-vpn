import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/freecore/notifier/freecore_activation_notifier.dart';
import 'package:hiddify/features/freecore/notifier/freecore_tg_login_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Экран логина через Telegram.
///
/// Flow:
///   1. На enter: notifier.start() → /api/login_init → получает state + login_url.
///   2. UI показывает "Открыть Telegram-бот", при клике запускает url_launcher.
///   3. Notifier поллит /api/login_check каждые 3с.
///   4. На confirmed: addProfileNotifier.addManual(sub_url), invalidate
///      freecoreActivatedProvider, navigate /home.
///   5. На expired/error — возможность retry.
class TgLoginPage extends HookConsumerWidget {
  const TgLoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(freecoreTgLoginProvider);

    // Auto-start при первом mount (не при retry — там пользователь сам нажмёт).
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (ref.read(freecoreTgLoginProvider) is TgLoginIdle) {
          ref.read(freecoreTgLoginProvider.notifier).start();
        }
      });
      return null;
    }, const []);

    // На confirmed — добавить профиль и перейти на /home.
    ref.listen<FreeCoreTgLoginState>(freecoreTgLoginProvider, (prev, next) async {
      if (next is TgLoginConfirmed && next.subUrl != null && next.subUrl!.isNotEmpty) {
        if (next.hasSubscription) {
          await ref.read(addProfileNotifierProvider.notifier).addManual(
                url: next.subUrl!,
                userOverride: const UserOverride(name: 'FreeCore VPN'),
              );
        }
        ref.invalidate(freecoreActivatedProvider);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (context.mounted) context.go('/home');
      }
    });

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            ref.read(freecoreTgLoginProvider.notifier).cancel();
            context.pop();
          },
        ),
        title: const Text('Вход через Telegram'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: _buildBody(context, ref, state, theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref, FreeCoreTgLoginState state, ThemeData theme) {
    return switch (state) {
      TgLoginIdle()         => _LoadingState(theme: theme, label: 'Готовим вход...'),
      TgLoginInitializing() => _LoadingState(theme: theme, label: 'Создаём ссылку для входа...'),
      TgLoginWaiting(:final loginUrl) => _WaitingState(theme: theme, loginUrl: loginUrl, state: state),
      TgLoginConfirmed(:final hasSubscription) => _ConfirmedState(theme: theme, hasSubscription: hasSubscription),
      TgLoginExpired() => _ErrorState(
        theme: theme,
        title: 'Срок ссылки истёк',
        message: 'Прошло больше 5 минут. Нажми кнопку ниже чтобы попробовать снова.',
        retryLabel: 'Попробовать снова',
        onRetry: () => ref.read(freecoreTgLoginProvider.notifier).start(),
      ),
      TgLoginError(:final code) => _ErrorState(
        theme: theme,
        title: 'Ошибка',
        message: _errorText(code),
        retryLabel: 'Попробовать снова',
        onRetry: () => ref.read(freecoreTgLoginProvider.notifier).start(),
      ),
    };
  }

  static String _errorText(String code) => switch (code) {
    'unsupported_platform' => 'Платформа не поддерживается',
    'no_network'           => 'Нет связи с сервером. Проверь интернет',
    'timeout'              => 'Сервер не отвечает. Попробуй ещё раз',
    'network'              => 'Сетевая ошибка',
    _                      => 'Не удалось начать вход: $code',
  };
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({required this.theme, required this.label});
  final ThemeData theme;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 80),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
      ],
    ),
  );
}

class _WaitingState extends HookWidget {
  const _WaitingState({required this.theme, required this.loginUrl, required this.state});
  final ThemeData theme;
  final String loginUrl;
  final TgLoginWaiting state;

  @override
  Widget build(BuildContext context) {
    // Live-обновление таймера каждую секунду.
    final tick = useState(0);
    useEffect(() {
      final t = Stream.periodic(const Duration(seconds: 1)).listen((_) => tick.value++);
      return t.cancel;
    }, const []);
    final remaining = state.remaining;
    final mm = remaining.inMinutes.toString().padLeft(2, '0');
    final ss = (remaining.inSeconds % 60).toString().padLeft(2, '0');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Center(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset('assets/freecore/app_icon.png', width: 96, height: 96, fit: BoxFit.cover),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Подтверди вход в боте',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          'Сейчас откроется Telegram. Бот пришлёт тебе сообщение с кнопкой\n«✅ Войти в FreeCore VPN» — нажми её. Возвращайся в это окно — мы сами всё подхватим.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          icon: const Icon(Icons.send),
          label: const Text('Открыть Telegram', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => UriUtils.tryLaunch(Uri.parse(loginUrl)),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.timer_outlined, size: 18, color: theme.hintColor),
            const SizedBox(width: 8),
            Text(
              'Истекает через $mm:$ss',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.8, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: 10),
            Text('Ждём подтверждения...', style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor)),
          ],
        ),
      ],
    );
  }
}

class _ConfirmedState extends StatelessWidget {
  const _ConfirmedState({required this.theme, required this.hasSubscription});
  final ThemeData theme;
  final bool hasSubscription;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 60),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle, size: 72, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          hasSubscription ? 'Вход подтверждён!' : 'Вход подтверждён',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          hasSubscription
              ? 'Загружаем твою подписку...'
              : 'У тебя нет активной подписки. Купи тариф в боте и возвращайся.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
        ),
      ],
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.theme,
    required this.title,
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });
  final ThemeData theme;
  final String title;
  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 60),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor, height: 1.4),
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: onRetry,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(retryLabel),
        ),
      ],
    ),
  );
}
