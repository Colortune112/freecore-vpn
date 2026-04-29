# FreeCore module — architecture

Внутреннее устройство `lib/features/freecore/`. Всё что специфично для FreeCore (не Hiddify-апстрим) — здесь. Точка пересечения с Hiddify ровно одна: `addProfileNotifierProvider.notifier.addManual()` после успеха активации/логина.

## 1. Структура файлов

| File | Роль |
|---|---|
| `data/freecore_constants.dart` | base URL, endpoint paths, SharedPreferences keys. Один источник правды для смены backend-хоста. |
| `data/freecore_storage.dart` | Обёртка над `SharedPreferences`. Хранит `device_id` (генерируется один раз), флаг `activated`, `activeCode`, `lastSyncAt`. Также — статический геттер `currentPlatform` (`windows`/`macos`/`android`/`linux`/`null`). |
| `data/freecore_api_client.dart` | Тонкий Dio-клиент. Методы `redeem()`, `sync()`, `loginInit()`, `loginCheck()`. Каждый метод возвращает sealed result type (`FreeCoreRedeemResult`, `FreeCoreLoginCheckResult`, …) — switch'ится через `switch (result)` в notifier. |
| `notifier/freecore_activation_notifier.dart` | State machine ввода ключа. States: `Idle → Submitting → Success \| Error`. Здесь же объявлены все Riverpod-провайдеры модуля (api/storage/activated/activation). |
| `notifier/freecore_tg_login_notifier.dart` | State machine TG-логина. States: `Idle → Initializing → Waiting → Confirmed \| Expired \| Error`. Поллит `/api/login_check` каждые 3 сек, общий TTL — 5 мин (приходит в `expires_in` от бэка). |
| `widget/activation_page.dart` | Экран `/activate`. Текстовое поле с авто-форматированием `FC-XXXXX-XXXXX-XXXXX`, кнопка "Активировать", кнопка "Войти через Telegram" (push на `/login-tg`). На успехе — `addProfileNotifier.addManual(subUrl)` + `context.go('/home')`. |
| `widget/tg_login_page.dart` | Экран `/login-tg`. Авто-старт `notifier.start()` на mount, кнопка "Открыть Telegram" (`url_launcher`), live-таймер `mm:ss`, retry на expired/error. |

## 2. Потоки

### 2.1 Activation by key

```
ActivationPage._KeyTextField (FC-XXXXX-XXXXX-XXXXX)
  → notifier.activate(rawCode)                       activation_notifier.dart:55
    → _validKeyFormat(code)                          activation_notifier.dart:95
    → storage.getOrCreateDeviceId()                  freecore_storage.dart:40
    → api.redeem(code, deviceId, platform)           freecore_api_client.dart:27
      → POST /api/redeem_external
    → on Success:
        storage.markActivated(code)                  freecore_storage.dart:60
        state = FreeCoreActivationSuccess(subUrl, ...)
ref.listen on Success (activation_page.dart:38):
  → addProfileNotifier.addManual(subUrl, name='FreeCore VPN')   activation_page.dart:40
  → ref.invalidate(freecoreActivatedProvider)        activation_page.dart:44
  → context.go('/home')                              activation_page.dart:46
```

### 2.2 TG login

```
ActivationPage → context.push('/login-tg')           activation_page.dart:123
TgLoginPage useEffect → notifier.start()             tg_login_page.dart:30
  → api.loginInit(deviceId, platform)                freecore_api_client.dart:60
    → POST /api/login_init
  → state = TgLoginWaiting(loginUrl, state, expiresAt)
  → _startPolling() — Timer.periodic(3 sec)          tg_login_notifier.dart:117

User taps "Открыть Telegram":
  → UriUtils.tryLaunch(loginUrl)                     tg_login_page.dart:178
  → opens tg://... → бот → callback "✅ Войти"

Каждые 3 сек:
  → api.loginCheck(state, deviceId, platform)        freecore_api_client.dart:87
    → POST /api/login_check
  → on Success(confirmed):
      pollTimer.cancel()
      storage.markActivated('tg_<tgId>')             tg_login_notifier.dart:143
      state = TgLoginConfirmed(subUrl, hasSubscription)
ref.listen on Confirmed (tg_login_page.dart:39):
  → addProfileNotifier.addManual(subUrl)             tg_login_page.dart:42 (только если hasSubscription)
  → ref.invalidate(freecoreActivatedProvider)
  → context.go('/home')
```

## 3. Router gate

`lib/core/router/go_router/routing_config_notifier.dart:68-95` — единственная точка входа для FreeCore-redirect. Сжатая логика:

```dart
final freecoreActivated = ref.read(freecoreActivatedProvider);
final isActivate = state.matchedLocation == '/activate';
final isTgLogin  = state.matchedLocation == '/login-tg';

if (!freecoreActivated) {
  return (isActivate || isTgLogin) ? null : '/activate';
}

// Активирован, но в drift нет ни одного профиля (TG-login без подписки,
// либо subscription URL отдал 404). Сбрасываем, возвращаем на /activate.
final hasProfile = ref.read(hasAnyProfileProvider).value;
if (hasProfile == false) {
  ref.read(freecoreStorageProvider).reset();
  ref.invalidate(freecoreActivatedProvider);
  return isActivate || isTgLogin ? null : '/activate';
}

if (isActivate || isTgLogin) return '/home';   // блокируем deep-link на /activate если уже OK
```

Регистрация роутов: `routing_config_notifier.dart:281` — `GoRoute(path: '/activate')` и парный `/login-tg`.

## 4. Backend contracts

Все запросы — JSON POST на `https://sub.optimizator-pc.ru:8443`. Сервер всегда отвечает `200 OK`; ошибки маркируются `{"ok": false, "error": "..."}`.

### POST /api/redeem_external

```json
// request
{ "code": "FC-3H7K9-P2N8M-Q5VXB", "device_id": "<43-char>", "platform": "macos" }

// success
{ "ok": true, "status": "redeemed",
  "sub_url": "https://sub.optimizator-pc.ru:8443/sub/<token>",
  "plan": "monthly", "expires_at": "2026-05-29T...Z",
  "servers": [{"id":"de1","name":"Germany","host":"..."}] }

// error
{ "ok": false, "error": "key_already_used" }
```

Идемпотентен: повтор с тем же `(code, device_id)` → `status: "already_redeemed_by_device"`.

### POST /api/login_init

```json
// request
{ "device_id": "...", "platform": "windows" }

// success
{ "ok": true, "state": "abc123...", "expires_in": 300,
  "login_url": "tg://resolve?domain=FreeCore_VPN_bot&start=login_abc123" }
```

### POST /api/login_check

```json
// request
{ "state": "abc123...", "device_id": "...", "platform": "windows" }

// pending
{ "ok": false, "error": "pending" }

// confirmed (с подпиской)
{ "ok": true, "status": "confirmed", "tg_id": -4611686018427387903,
  "sub_url": "...", "plan": "monthly", "expires_at": "...",
  "servers": [...], "migrated": false }

// expired
{ "ok": false, "error": "expired" }
```

`tg_id` может быть отрицательным (synthetic) если юзер до этого использовал desktop без TG — это ОК.

### POST /api/sync_external

```json
// request
{ "device_id": "..." }

// success
{ "ok": true, "active": true, "sub_url": "...", "plan": "monthly",
  "expires_at": "...", "servers": [...] }
```

Дёргается периодически (план: раз в ~6 часов / при старте). Сейчас вызывается только из `redeem`-flow.

## 5. Provider graph

```
sharedPreferencesProvider (Hiddify-provided)        # core/preferences/preferences_provider.dart
  └─> freecoreStorageProvider                       # activation_notifier.dart:110
        └─> freecoreActivatedProvider               # activation_notifier.dart:118 (router watches this)

freecoreApiClientProvider                           # activation_notifier.dart:106 (lazy singleton)

freecoreActivationProvider (StateNotifier)          # activation_notifier.dart:122
  - depends on: freecoreApiClient + freecoreStorage
  - state: FreeCoreIdle | Submitting | Success | Error

freecoreTgLoginProvider (StateNotifier.autoDispose) # tg_login_notifier.dart:160
  - depends on: freecoreApiClient + freecoreStorage
  - autoDispose → poll timer гарантированно отменяется при уходе с /login-tg
  - state: TgLoginIdle | Initializing | Waiting | Confirmed | Expired | Error
```

`.requireValue` на `sharedPreferencesProvider` безопасен, потому что `bootstrap.dart` await'ит prefs до первого `runApp()`.

## 6. Где интегрируемся с Hiddify-core

**Один method, одна точка**:

```dart
ref.read(addProfileNotifierProvider.notifier).addManual(
  url: subUrl,
  userOverride: const UserOverride(name: 'FreeCore VPN'),
);
```

Вызывается из:
- `widget/activation_page.dart:40` — после успеха `/api/redeem_external`.
- `widget/tg_login_page.dart:42` — после `TgLoginConfirmed` если `hasSubscription`.

`addManual()` (из `lib/features/profile/notifier/profile_notifier.dart`) скачает подписку, распарсит VLESS+Reality, сохранит в drift и пометит активным (если это первый профиль). Дальше Hiddify-home отрисует свою стандартную connect-кнопку — мы лишь делаем `context.go('/home')` после 600мс задержки на upsertRemote.

Никаких других хуков в Hiddify-core мы не делаем. Никаких patch'ей `lib/features/profile/`, `lib/features/connection/`, `lib/features/proxy/`. Если что-то ломается в connect/disconnect — это апстрим Hiddify, не FreeCore.

## 7. Где можно сломаться

- **Poll timer leak**: если `freecoreTgLoginProvider` перестанет быть `autoDispose`, либо если notifier не вызовет `_pollTimer?.cancel()` в `dispose()` — таймер будет жить вечно после ухода со страницы. См. `tg_login_notifier.dart:81`.
- **SharedPreferences race на старте**: `freecoreStorageProvider` использует `.requireValue` на `sharedPreferencesProvider`. Если кто-то изменит порядок инициализации в `bootstrap.dart` и runApp стартует до prefs-future — упадёт `StateError`.
- **Synthetic tg_id и `bot.get_chat()`**: на бэке при TG-логине есть особенность — `external_devices` юзеры имеют отрицательный `tg_id` вне Telegram-range; `bot.get_chat(tg_id)` для них упадёт. На бэке это уже фиксилось (см. `vpn_bot/handlers/redeem.py`), но если будут добавлять новые места, дёргающие `get_chat` — не забывать про synthetic-юзеров.
- **Miss profile fallback**: если `addManual()` молча провалится (subscription URL вернул 404 / parse error), мы помечены `activated=true`, но в drift ничего нет → router-gate (см. секцию 3) увидит `hasProfile == false`, дёрнет `storage.reset()` и вернёт юзера на `/activate`. Это сделано намеренно — но **если юзер сидит на `/home`**, а профиль удалили вручную, redirect сработает только при следующей навигации (router использует `read`, не `watch` для `hasAnyProfileProvider`).
- **Key format regex слишком строгий**: алфавит у бэка — `[A-Z2-9]` (без `0/O/1/I/L`), у клиента — `[A-Z0-9]`. Юзер физически не сможет ввести `0/1` через `_KeyInputFormatter` (autoCaps + filter), но `O/I/L` пропустит — бэк ответит `key_not_found`. Можно ужесточить regex в `activation_notifier.dart:99`.
- **Hiddify-core dylib mismatch**: при апгрейде Flutter SDK (>3.41.8) prebuilt-libs могут несоответствовать ABI → runtime crash. Перед апгрейдом проверять `dependencies.properties` в `hiddify-app/`.
- **expires_in переопределение**: бэк отдаёт `expires_in: 300`, клиент конвертит в `DateTime.now() + duration`. Если у юзера часы скошены на >5 мин — `TgLoginWaiting.remaining` будет либо мгновенно `Zero` либо вечно положительным. Не критично, но если будут жалобы "expired сразу" — смотреть тут (`tg_login_notifier.dart:104`).
