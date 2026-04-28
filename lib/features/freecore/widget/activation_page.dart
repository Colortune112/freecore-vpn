import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:go_router/go_router.dart';
import 'package:hiddify/features/freecore/data/freecore_constants.dart';
import 'package:hiddify/features/freecore/notifier/freecore_activation_notifier.dart';
import 'package:hiddify/features/profile/model/profile_entity.dart';
import 'package:hiddify/features/profile/notifier/profile_notifier.dart';
import 'package:hiddify/utils/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Главный экран при первом запуске FreeCore-клиента.
///
/// Юзер вводит код активации (формат FC-XXXXX-XXXXX-XXXXX). При успехе:
///  1. notifier сохраняет sub_url + activated=true в prefs
///  2. invalidate(freecoreActivatedProvider) → router redirect пропустит /activate
///  3. context.go('/home') — Hiddify intro/home подхватывает дальше
///
/// Если пользователь уже активирован (например, открыл deep link на /activate
/// руками) — экран показывает отдельный layout "уже активировано → перейти на главный".
class ActivationPage extends HookConsumerWidget {
  const ActivationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final controller = useTextEditingController();
    final state = ref.watch(freecoreActivationProvider);

    // Когда активация прошла:
    //   1. Программно добавляем sub_url как Hiddify-профиль (без bottomSheet) —
    //      Hiddify скачает подписку, распарсит VLESS+Reality, занесёт в drift DB
    //      и (так как профиль первый) сразу пометит активным.
    //   2. invalidate(freecoreActivatedProvider) → router-redirect перестанет
    //      отправлять на /activate и пропустит на /home.
    //   3. context.go('/home') — даём 600мс на upsertRemote, дальше Hiddify-home
    //      сам отрисует connect button с готовым активным профилем.
    ref.listen<FreeCoreActivationState>(freecoreActivationProvider, (prev, next) async {
      if (next is FreeCoreActivationSuccess && next.subUrl.isNotEmpty) {
        await ref.read(addProfileNotifierProvider.notifier).addManual(
              url: next.subUrl,
              userOverride: const UserOverride(name: 'FreeCore VPN'),
            );
        ref.invalidate(freecoreActivatedProvider);
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (context.mounted) context.go('/home');
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  _Logo(theme: theme),
                  const SizedBox(height: 24),
                  Text(
                    'FreeCore VPN',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Введите ключ активации',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                  ),
                  const SizedBox(height: 32),
                  _KeyTextField(controller: controller, enabled: state is! FreeCoreSubmitting),
                  const SizedBox(height: 16),
                  _StatusLine(state: state),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: state is FreeCoreSubmitting
                        ? null
                        : () {
                            FocusScope.of(context).unfocus();
                            ref.read(freecoreActivationProvider.notifier).activate(controller.text);
                          },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: state is FreeCoreSubmitting
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                          )
                        : const Text('Активировать', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: Divider(color: theme.dividerColor)),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'или',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                        ),
                      ),
                      Expanded(child: Divider(color: theme.dividerColor)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.send_outlined),
                    label: const Text('Войти через Telegram', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: theme.colorScheme.primary, width: 1.4),
                      foregroundColor: theme.colorScheme.primary,
                    ),
                    onPressed: state is FreeCoreSubmitting ? null : () => context.push('/login-tg'),
                  ),
                  const SizedBox(height: 24),
                  _SupportLink(),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Image.asset(
          'assets/freecore/app_icon.png',
          width: 120,
          height: 120,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _KeyTextField extends StatelessWidget {
  const _KeyTextField({required this.controller, required this.enabled});
  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextField(
      controller: controller,
      enabled: enabled,
      autofocus: true,
      textAlign: TextAlign.center,
      textCapitalization: TextCapitalization.characters,
      maxLength: 20, // FC- + 5 + - + 5 + - + 5 = 20
      inputFormatters: [_KeyInputFormatter()],
      style: theme.textTheme.titleMedium?.copyWith(
        letterSpacing: 2,
        fontWeight: FontWeight.w600,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      decoration: InputDecoration(
        hintText: 'FC-XXXXX-XXXXX-XXXXX',
        counterText: '',
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      ),
    );
  }
}

/// Авто-форматирование ввода ключа:
/// - Удаляет невалидные символы (оставляет [A-Z2-9])
/// - Приводит к UPPERCASE
/// - Вставляет дефисы после FC, после 5го и после 10го значимого символа
class _KeyInputFormatter extends TextInputFormatter {
  static final _allowed = RegExp('[A-Z0-9]');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final raw = newValue.text.toUpperCase();
    final stripped = raw.split('').where(_allowed.hasMatch).join();

    // Гарантируем prefix FC. Если юзер вставил без него — добавим.
    String body = stripped;
    if (body.startsWith('FC')) body = body.substring(2);

    final blocks = <String>[];
    for (var i = 0; i < body.length && blocks.length < 3; i += 5) {
      final end = (i + 5).clamp(0, body.length);
      blocks.add(body.substring(i, end));
    }
    final formatted = ['FC', ...blocks].where((s) => s.isNotEmpty).join('-');
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.state});
  final FreeCoreActivationState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, text, color) = switch (state) {
      FreeCoreIdle()        => (null,                       null,                                    null),
      FreeCoreSubmitting()  => (Icons.cloud_sync_outlined,  'Проверяем ключ...',                     theme.hintColor),
      FreeCoreActivationSuccess(:final repeatedActivation) => (
        Icons.check_circle_outline,
        repeatedActivation ? 'Этот ключ уже привязан к устройству' : 'Активировано! Открываем VPN...',
        theme.colorScheme.primary,
      ),
      FreeCoreActivationError(:final code) => (
        Icons.error_outline,
        _errorText(code),
        theme.colorScheme.error,
      ),
    };

    if (text == null) return const SizedBox(height: 24);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  static String _errorText(String code) => switch (code) {
    'invalid_code_format'  => 'Неверный формат ключа. Должен быть FC-XXXXX-XXXXX-XXXXX',
    'invalid_device_id'    => 'Внутренняя ошибка устройства. Перезапустите приложение',
    'invalid_platform'     => 'Платформа не поддерживается',
    'unsupported_platform' => 'Платформа не поддерживается (только Win/Mac/Android/Linux)',
    'key_not_found'        => 'Ключ не найден. Проверьте — возможно, опечатка',
    'key_already_used'     => 'Ключ уже использован на другом устройстве',
    'key_expired'          => 'Срок действия ключа истёк',
    'plan_unknown'         => 'Тариф ключа не распознан. Напишите в поддержку',
    'provisioning_failed'  => 'Активация прошла, но настройка серверов не удалась. Попробуйте через минуту',
    'storage_not_ready'    => 'Подождите секунду и нажмите ещё раз',
    'timeout'              => 'Сервер не отвечает. Проверьте интернет',
    'no_network'           => 'Нет связи с сервером. Проверьте интернет',
    'network'              => 'Сетевая ошибка. Попробуйте ещё раз',
    _                      => 'Не удалось активировать: $code',
  };
}

class _SupportLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => UriUtils.tryLaunch(Uri.parse(FreeCoreApi.supportTelegram)),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text.rich(
          TextSpan(
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
            children: [
              const TextSpan(text: 'Нет ключа? '),
              TextSpan(
                text: '@FreeCore_VPN_bot',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
