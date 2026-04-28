import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hiddify/features/freecore/data/freecore_api_client.dart';
import 'package:hiddify/features/freecore/data/freecore_storage.dart';
import 'package:hiddify/features/freecore/notifier/freecore_activation_notifier.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// State machine для экрана TG-логина.
///
///   idle → initializing → waiting (поллит каждые 3с) → confirmed | expired | error
///
/// Поллинг останавливается при confirmed/expired/error или когда юзер
/// уходит со страницы (provider auto-dispose). Suborbital: общая длительность
/// сессии — 5 минут (TTL на бэке), потом expired.
@immutable
sealed class FreeCoreTgLoginState {
  const FreeCoreTgLoginState();
}

class TgLoginIdle extends FreeCoreTgLoginState {
  const TgLoginIdle();
}

class TgLoginInitializing extends FreeCoreTgLoginState {
  const TgLoginInitializing();
}

class TgLoginWaiting extends FreeCoreTgLoginState {
  const TgLoginWaiting({
    required this.loginUrl,
    required this.state,
    required this.startedAt,
    required this.expiresAt,
  });
  final String loginUrl;
  final String state;
  final DateTime startedAt;
  final DateTime expiresAt;

  Duration get remaining {
    final now = DateTime.now();
    return now.isAfter(expiresAt) ? Duration.zero : expiresAt.difference(now);
  }
}

class TgLoginConfirmed extends FreeCoreTgLoginState {
  const TgLoginConfirmed({
    required this.tgId,
    required this.subUrl,
    required this.hasSubscription,
    required this.plan,
    required this.expiresAt,
  });
  final int tgId;
  final String? subUrl;
  /// false если юзер залогинился, но не имеет активной подписки (нужно купить
  /// в боте сначала). UI должен показать "вход успешен, но нет подписки".
  final bool hasSubscription;
  final String? plan;
  final String? expiresAt;
}

class TgLoginExpired extends FreeCoreTgLoginState {
  const TgLoginExpired();
}

class TgLoginError extends FreeCoreTgLoginState {
  const TgLoginError(this.code);
  final String code;
}

class FreeCoreTgLoginNotifier extends StateNotifier<FreeCoreTgLoginState> {
  FreeCoreTgLoginNotifier(this._api, this._storage) : super(const TgLoginIdle());

  final FreeCoreApiClient _api;
  final FreeCoreStorage _storage;
  Timer? _pollTimer;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  /// Старт TG-логина. Вызывает /api/login_init, затем сразу начинает поллинг.
  Future<void> start() async {
    if (state is TgLoginInitializing || state is TgLoginWaiting) return;

    state = const TgLoginInitializing();

    final platform = FreeCoreStorage.currentPlatform;
    if (platform == null) {
      state = const TgLoginError('unsupported_platform');
      return;
    }

    final deviceId = await _storage.getOrCreateDeviceId();
    final init = await _api.loginInit(deviceId: deviceId, platform: platform);

    switch (init) {
      case FreeCoreLoginInitSuccess(state: final stateId, :final loginUrl, :final expiresIn):
        final now = DateTime.now();
        final expires = now.add(Duration(seconds: expiresIn));
        state = TgLoginWaiting(
          loginUrl:  loginUrl,
          state:     stateId,
          startedAt: now,
          expiresAt: expires,
        );
        _startPolling(stateId, deviceId, platform);
      case FreeCoreLoginInitError(:final code):
        state = TgLoginError(code);
    }
  }

  void _startPolling(String stateId, String deviceId, String platform) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final cur = state;
      if (cur is! TgLoginWaiting) {
        _pollTimer?.cancel();
        return;
      }
      if (DateTime.now().isAfter(cur.expiresAt)) {
        _pollTimer?.cancel();
        state = const TgLoginExpired();
        return;
      }

      final res = await _api.loginCheck(state: stateId, deviceId: deviceId, platform: platform);
      switch (res) {
        case FreeCoreLoginCheckSuccess():
          _pollTimer?.cancel();
          state = TgLoginConfirmed(
            tgId:            res.tgId,
            subUrl:          res.subUrl,
            hasSubscription: res.subUrl != null && res.plan != null,
            plan:            res.plan,
            expiresAt:       res.expiresAt,
          );
          // Помечаем activated в локальном storage — router-redirect пропустит.
          await _storage.markActivated('tg_${res.tgId}');
        case FreeCoreLoginCheckPending(:final code):
          if (code == 'expired' || code == 'session_not_found') {
            _pollTimer?.cancel();
            state = const TgLoginExpired();
          }
          // 'pending' | 'network' | 'timeout' — продолжаем поллить
      }
    });
  }

  void cancel() {
    _pollTimer?.cancel();
    state = const TgLoginIdle();
  }
}

final freecoreTgLoginProvider =
    StateNotifierProvider.autoDispose<FreeCoreTgLoginNotifier, FreeCoreTgLoginState>((ref) {
  return FreeCoreTgLoginNotifier(
    ref.watch(freecoreApiClientProvider),
    ref.watch(freecoreStorageProvider),
  );
});
