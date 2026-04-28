import 'package:flutter/foundation.dart';
import 'package:hiddify/core/preferences/preferences_provider.dart';
import 'package:hiddify/features/freecore/data/freecore_api_client.dart';
import 'package:hiddify/features/freecore/data/freecore_storage.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// State machine для экрана активации.
///
///   idle → submitting → success | error → idle (ретрай)
///
/// State хранится в памяти; persisted-флаг "активирован" живёт в FreeCoreStorage
/// (SharedPreferences). При успехе UI должен дёрнуть router-redirect (через
/// `freecoreActivatedProvider`), который уведёт юзера на /home.
@immutable
sealed class FreeCoreActivationState {
  const FreeCoreActivationState();
}

class FreeCoreIdle extends FreeCoreActivationState {
  const FreeCoreIdle();
}

class FreeCoreSubmitting extends FreeCoreActivationState {
  const FreeCoreSubmitting();
}

class FreeCoreActivationSuccess extends FreeCoreActivationState {
  const FreeCoreActivationSuccess({
    required this.subUrl,
    required this.plan,
    required this.expiresAt,
    required this.servers,
    required this.repeatedActivation,
  });
  final String subUrl;
  final String plan;
  final String? expiresAt;
  final List<FreeCoreServer> servers;
  /// true если сервер вернул `already_redeemed_by_device`.
  final bool repeatedActivation;
}

class FreeCoreActivationError extends FreeCoreActivationState {
  const FreeCoreActivationError(this.code);
  final String code;
}

class FreeCoreActivationNotifier extends StateNotifier<FreeCoreActivationState> {
  FreeCoreActivationNotifier(this._api, this._storage) : super(const FreeCoreIdle());

  final FreeCoreApiClient _api;
  final FreeCoreStorage _storage;

  /// Активация ключа. [rawCode] нормализуется (trim, upper).
  Future<void> activate(String rawCode) async {
    state = const FreeCoreSubmitting();

    final code = rawCode.trim().toUpperCase();
    if (!_validKeyFormat(code)) {
      state = const FreeCoreActivationError('invalid_code_format');
      return;
    }

    final platform = FreeCoreStorage.currentPlatform;
    if (platform == null) {
      state = const FreeCoreActivationError('unsupported_platform');
      return;
    }

    final deviceId = await _storage.getOrCreateDeviceId();

    final result = await _api.redeem(
      code:     code,
      deviceId: deviceId,
      platform: platform,
    );

    switch (result) {
      case FreeCoreRedeemSuccess():
        await _storage.markActivated(code);
        state = FreeCoreActivationSuccess(
          subUrl:             result.subUrl,
          plan:               result.plan,
          expiresAt:          result.expiresAt,
          servers:            result.servers,
          repeatedActivation: result.status == 'already_redeemed_by_device',
        );
      case FreeCoreRedeemError():
        state = FreeCoreActivationError(result.code);
    }
  }

  void reset() => state = const FreeCoreIdle();

  static bool _validKeyFormat(String code) {
    // Структурный формат: FC-XXXXX-XXXXX-XXXXX. Алфавит строгий [A-Z2-9] без
    // 0/O/1/I/L проверит бэкенд по списку известных кодов в БД, нам важна только
    // структура (юзер ввёл правильное число дефисов и блоков).
    final re = RegExp(r'^FC-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$');
    return re.hasMatch(code);
  }
}

// ---- providers ----

final freecoreApiClientProvider = Provider<FreeCoreApiClient>((ref) => FreeCoreApiClient());

/// Singleton storage поверх sharedPreferencesProvider Hiddify.
/// `.requireValue` безопасен потому что bootstrap.dart awaitит prefs до запуска UI.
final freecoreStorageProvider = Provider<FreeCoreStorage>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider).requireValue;
  return FreeCoreStorage(prefs);
});

/// Локальный флаг "клиент активирован" — для router redirect.
/// Меняется только через FreeCoreStorage.markActivated(); провайдер
/// автоматически перечитает при следующем `ref.read`/`ref.watch`.
final freecoreActivatedProvider = Provider<bool>((ref) {
  return ref.watch(freecoreStorageProvider).isActivated;
});

final freecoreActivationProvider =
    StateNotifierProvider<FreeCoreActivationNotifier, FreeCoreActivationState>((ref) {
  return FreeCoreActivationNotifier(
    ref.watch(freecoreApiClientProvider),
    ref.watch(freecoreStorageProvider),
  );
});
