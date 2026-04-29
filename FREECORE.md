# FreeCore VPN — клиент

## Что это

Брендированный VPN-клиент **FreeCore VPN**, форк [hiddify/hiddify-app](https://github.com/hiddify/hiddify-app) v4.1.2 (GPL-3.0). Поддерживает Windows / macOS / Linux / Android. **iOS не собирается** (санкции, Apple Developer не работает с РФ-команды). Backend и активация — наши, всё остальное (sing-box ядро, drift DB, UI shell) — апстримный Hiddify, который мы тонко переопределяем поверх.

## Tech stack

- **Flutter 3.41.8 / Dart 3.11** (зафиксировано в CI)
- **Riverpod** (codegen через `dart run build_runner build`)
- **drift** — локальная БД профилей (наследуется от Hiddify)
- **sing-box** через `hiddify-core` (prebuilt dylib/so/dll, тянутся из апстрима)
- **dio** — наш API-клиент (`lib/features/freecore/data/freecore_api_client.dart`)
- **go_router** — навигация (`lib/core/router/go_router/`)

## Что мы изменили поверх Hiddify (high-level)

- **Брендинг**: имя приложения (`FreeCore VPN`), цвет, иконка (`assets/freecore/app_icon.png`), splash. Win-exe переименован, NSIS installer собран отдельно.
- **Активация по ключу**: новый экран `ActivationPage` ввода `FC-XXXXX-XXXXX-XXXXX` → `POST /api/redeem_external` → сохраняем `sub_url` как Hiddify-профиль через `addProfileNotifier.addManual()`.
- **Логин через Telegram**: альтернатива ключу — `POST /api/login_init` (получаем deep-link на бот) → `url_launcher` → поллинг `POST /api/login_check` каждые 3 сек / TTL 5 минут.
- **Mobile-only layout на всех платформах**: `isMobileBreakpoint → true`, скрыт desktop-sidebar.
- **Скрытые sidebar entries**: Logs, About, Profiles — пользователь работает с одной "большой кнопкой connect".
- **Connect button**: door silhouette + `BlendMode` поверх Hiddify-state (вместо стрелки).
- **Router gate**: redirect на `/activate` если `freecoreActivated == false`, плюс fallback на `/activate` если активирован, но в drift нет ни одного профиля (например, юзер вошёл через TG, но подписки в боте нет).
- **CI**: свой `freecore-release.yml` для тегов `v*.*.*`, NSIS-installer для Windows.

## Где живёт наш код

Весь FreeCore-специфичный код изолирован в `hiddify-app/lib/features/freecore/`:

```
lib/features/freecore/
├── data/
│   ├── freecore_constants.dart        # base URL, paths, prefs keys
│   ├── freecore_storage.dart          # SharedPreferences-обёртка (device_id, флаги активации)
│   └── freecore_api_client.dart       # Dio-клиент: redeem/sync/loginInit/loginCheck + sealed result types
├── notifier/
│   ├── freecore_activation_notifier.dart  # state machine ввода ключа + Riverpod providers
│   └── freecore_tg_login_notifier.dart    # state machine TG-логина с поллингом
└── widget/
    ├── activation_page.dart           # экран /activate (поле ключа + кнопка TG)
    └── tg_login_page.dart             # экран /login-tg (ожидание confirm)
```

Точечные правки за пределами `features/freecore/`:

- `lib/core/router/go_router/routing_config_notifier.dart` — redirect-gate + регистрация роутов `/activate`, `/login-tg`.
- `pubspec.yaml` — название приложения, иконка, версия.
- ассеты — `assets/freecore/app_icon.png`, splash.
- `windows/`, `macos/`, `linux/`, `android/` — переименование bundle/exe/applicationId, иконки.

Подробное описание модуля — см. `hiddify-app/lib/features/freecore/ARCHITECTURE.md`.

## Как собрать локально (macOS)

Pre-requisites:

```bash
# Xcode CLT (для macos/ios target tooling, dylib symbols)
xcode-select --install

# Flutter 3.41.8 (через fvm рекомендуется)
fvm install 3.41.8 && fvm use 3.41.8

# ImageMagick для пересборки иконок (опционально)
brew install imagemagick
```

Сборка и запуск:

```bash
cd freecore-client/hiddify-app
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run -d macos
```

Релизный билд:

```bash
flutter build macos --release
flutter build apk    --release            # Android
flutter build linux  --release            # Linux
flutter build windows --release           # только на Windows-хосте
```

Hiddify-core dylib подтягивается на этапе `flutter pub get` через `dependencies.properties` — если падает с "library not loaded", смотри `hiddify-core/` и Makefile апстрима.

## CI

`/.github/workflows/freecore-release.yml`:

- Триггер: push тега `v*.*.*` (например `v1.0.3`) либо ручной `workflow_dispatch`.
- Matrix: `macos-14` (Apple Silicon), `windows-latest`, `ubuntu-22.04` (linux + android).
- Артефакты: `FreeCoreVPN-macos.zip`, `FreeCoreVPN-windows.zip` (+ NSIS `.exe` installer), `FreeCoreVPN-linux.zip`, `FreeCoreVPN-android.apk`.
- На Linux-runner ставит зависимости (`libgtk-3-dev`, `libwebkit2gtk-4.1-dev`, `libcurl4-openssl-dev`, `libc-ares-dev` — последние два нужны sentry-native).
- `FLUTTER_VERSION: 3.41.8` зафиксирован в `env`.

Чтобы выкатить релиз:

```bash
git tag v1.0.4 && git push origin v1.0.4
```

GitHub соберёт все 4 платформы и приклеит артефакты к Release-объекту.

## Релизы

https://github.com/Colortune112/freecore-vpn/releases

## Бэкенд API

Все эндпоинты живут на `https://sub.optimizator-pc.ru:8443` (Caddy reverse-proxy → Windows-сервер `194.87.55.199:8080`). Сервер всегда возвращает `200 OK`; ошибочные кейсы — `{"ok": false, "error": "..."}`. Идентификация — по `device_id` (генерится клиентом, ~256 бит энтропии, base64url, regex `[A-Za-z0-9_-]{8,128}`).

| Method | Path | Назначение |
|---|---|---|
| POST | `/api/redeem_external` | Активация ключа `FC-XXXXX-XXXXX-XXXXX`. Body: `{code, device_id, platform}`. Success: `{ok, status, sub_url, plan, expires_at, servers[]}`. Идемпотентен по `(code, device_id)` — повторный запрос вернёт `status="already_redeemed_by_device"`. |
| POST | `/api/sync_external` | Обновление состояния подписки. Body: `{device_id}`. Success: `{ok, active, sub_url, plan, expires_at, servers[]}`. Дёргается раз в ~6 часов или при старте. |
| POST | `/api/login_init` | Старт TG-логина. Body: `{device_id, platform}`. Success: `{ok, state, login_url, expires_in}` (TTL 300 сек). `login_url` — deep-link `tg://resolve?domain=...&start=login_<state>`. |
| POST | `/api/login_check` | Поллинг сессии. Body: `{state, device_id, platform}`. Pending: `{ok:false, error:"pending"}`. Confirmed: `{ok, status:"confirmed", tg_id, sub_url?, plan?, expires_at?, servers[], migrated}`. |

Полный контракт — `/Users/romantungushbaev/Documents/vpnproject/project_explain.md` → секция "FreeCore Desktop/Mobile клиент".

Поддерживаемые `platform`-значения: `windows | macos | android | linux`. iOS/Web не принимаются.

## Известные ограничения / TODO

- **Нет code-signing**:
  - macOS — нет Apple Developer ID, при первом запуске юзер видит Gatekeeper warning, нужно правый клик → Открыть.
  - Windows — нет EV-сертификата, SmartScreen ругается. Можно купить sectigo код-сигн за ~$200/год.
- **GeoIP в bundled sing-box устаревшая**: московский трафик иногда определяется как DE/NL — косметика, не влияет на маршрутизацию (она по `geosite:ru` не по `geoip`). Обновлять через `geoip.db` от sagernet раз в полгода.
- **Hiddify-core dylib — внешняя зависимость**: тянем prebuilt библиотеки из upstream `hiddify/hiddify-core` (см. `dependencies.properties`). Если они снимут тег или сломают ABI — наш билд встанет. План B: форкнуть и собирать самим (Go + sing-box патчи).
- **device_id привязан к SharedPreferences**: после переустановки ОС юзер получит новый `device_id` и не сможет реактивировать тот же ключ (`key_already_used`). Решается фолбэком через поддержку (вручную сбросить `external_devices` row на бэке).
- **Нет flutter_secure_storage**: device_id в SharedPreferences (DPAPI / Keychain / encrypted XML / `~/.config`) — приемлемо для MVP, но не secure-by-default.
- **iOS не собирается**: убрана из CI-matrix. Если нужно — придётся развернуть отдельную CI на Apple Dev account другой страны.
