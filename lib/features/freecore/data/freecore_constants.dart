/// FreeCore VPN — клиент-серверный контракт.
///
/// Backend живёт на Windows-сервере 194.87.55.199:8080 (внутренний),
/// Caddy reverse-proxy выставляет наружу как https://sub.optimizator-pc.ru:8443.
/// При смене эндпоинта меняй ТОЛЬКО эту константу.
class FreeCoreApi {
  static const String baseUrl = 'https://sub.optimizator-pc.ru:8443';

  static const String redeemPath = '/api/redeem_external';
  static const String syncPath   = '/api/sync_external';

  static String get supportTelegram => 'https://t.me/FreeCore_VPN_bot';
}

/// SharedPreferences keys для FreeCore-локального состояния.
/// Префикс `freecore.` отделяет от Hiddify-prefs (которые могут начинаться с `app.` и пр.).
class FreeCorePrefsKeys {
  static const String deviceId    = 'freecore.deviceId';
  static const String activated   = 'freecore.activated';
  static const String lastSyncAt  = 'freecore.lastSyncAtMillis';
  static const String platform    = 'freecore.platform';
  static const String activeCode  = 'freecore.activeCode';
}
