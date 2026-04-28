import 'dart:io';
import 'dart:math';

import 'package:hiddify/features/freecore/data/freecore_constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Локальное состояние FreeCore-клиента (device_id, флаги активации).
///
/// device_id генерируется один раз при первом запуске и сохраняется. Если юзер
/// переустановит ОС — получит новый device_id и не сможет реактивировать тот же
/// ключ (бэкенд вернёт `key_already_used`). Это **известное ограничение MVP** —
/// для расширенного фолбэка (поддержка-разблокировка) нужна дополнительная логика
/// на бэке (см. project_explain.md → "FreeCore Desktop/Mobile клиент").
///
/// Хранится в SharedPreferences (DPAPI на Windows, Keychain на macOS, encrypted
/// XML на Android, ~/.config на Linux). Это компромисс MVP — для полностью
/// secure хранения позже подключим flutter_secure_storage.
class FreeCoreStorage {
  FreeCoreStorage(this._prefs);

  final SharedPreferences _prefs;

  static Future<FreeCoreStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return FreeCoreStorage(prefs);
  }

  /// Текущая платформа в формате бэка: windows | macos | android | linux.
  /// Возвращает null если запущено на iOS/Web — там redeem_external не работает.
  static String? get currentPlatform {
    if (Platform.isWindows) return 'windows';
    if (Platform.isMacOS)   return 'macos';
    if (Platform.isAndroid) return 'android';
    if (Platform.isLinux)   return 'linux';
    return null;
  }

  /// Получает существующий device_id или генерирует новый. Хранится pending —
  /// если юзер бросит активацию, при следующем запуске ID будет тот же.
  Future<String> getOrCreateDeviceId() async {
    final existing = _prefs.getString(FreeCorePrefsKeys.deviceId);
    if (existing != null && existing.length >= 8) return existing;

    // 32 байта энтропии в base64url-style без `=` — попадает в [A-Za-z0-9_-]{43}
    // что соответствует regex'у бэка [A-Za-z0-9_-]{8,128}.
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-';
    final id = bytes.map((b) => chars[b % chars.length]).join();

    await _prefs.setString(FreeCorePrefsKeys.deviceId, id);
    await _prefs.setString(FreeCorePrefsKeys.platform, currentPlatform ?? '');
    return id;
  }

  bool get isActivated => _prefs.getBool(FreeCorePrefsKeys.activated) ?? false;

  String? get activeCode => _prefs.getString(FreeCorePrefsKeys.activeCode);

  Future<void> markActivated(String code) async {
    await _prefs.setBool(FreeCorePrefsKeys.activated, true);
    await _prefs.setString(FreeCorePrefsKeys.activeCode, code);
    await _prefs.setInt(FreeCorePrefsKeys.lastSyncAt, DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> markSynced() async {
    await _prefs.setInt(FreeCorePrefsKeys.lastSyncAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// Только для админа/девелопера: сбросить активацию (например, для тестов).
  Future<void> reset() async {
    await _prefs.remove(FreeCorePrefsKeys.activated);
    await _prefs.remove(FreeCorePrefsKeys.activeCode);
    await _prefs.remove(FreeCorePrefsKeys.lastSyncAt);
    // device_id оставляем — он стабилен между переактивациями.
  }
}
