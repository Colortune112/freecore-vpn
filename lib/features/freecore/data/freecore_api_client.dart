import 'package:dio/dio.dart';
import 'package:hiddify/features/freecore/data/freecore_constants.dart';

/// Тонкий клиент над Dio для двух FreeCore endpoints.
///
/// Сервер ВСЕГДА отвечает 200 OK, ошибочные кейсы — `{"ok": false, "error": "..."}`.
/// Поэтому вместо HTTP-кода смотрим на поле `ok` в JSON.
class FreeCoreApiClient {
  FreeCoreApiClient([Dio? dio])
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: FreeCoreApi.baseUrl,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15),
                headers: {'Content-Type': 'application/json'},
                // Не throw'аем на не-2xx — бэк может вернуть 400/500 c JSON,
                // мы хотим парсить body вместо exception-flow.
                validateStatus: (_) => true,
              ),
            );

  final Dio _dio;

  /// POST /api/redeem_external — активация ключа.
  /// При успехе возвращает [FreeCoreRedeemSuccess], иначе [FreeCoreRedeemError].
  Future<FreeCoreRedeemResult> redeem({
    required String code,
    required String deviceId,
    required String platform,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        FreeCoreApi.redeemPath,
        data: {
          'code':      code,
          'device_id': deviceId,
          'platform':  platform,
        },
      );
      final body = res.data ?? const {};
      if (body['ok'] == true) {
        return FreeCoreRedeemSuccess(
          status:    body['status']?.toString() ?? 'redeemed',
          subUrl:    body['sub_url']?.toString() ?? '',
          plan:      body['plan']?.toString() ?? '',
          expiresAt: body['expires_at']?.toString(),
          servers:   _parseServers(body['servers']),
        );
      }
      return FreeCoreRedeemError(body['error']?.toString() ?? 'unknown', httpStatus: res.statusCode);
    } on DioException catch (e) {
      return FreeCoreRedeemError(_dioErrorCode(e), httpStatus: e.response?.statusCode);
    } catch (_) {
      return const FreeCoreRedeemError('network');
    }
  }

  /// POST /api/sync_external — обновить состояние подписки по device_id.
  /// Идемпотентен, безопасен для частого вызова. Если устройство не активировано
  /// (404) — возвращает [FreeCoreSyncError('device_not_registered')].
  Future<FreeCoreSyncResult> sync({required String deviceId}) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        FreeCoreApi.syncPath,
        data: {'device_id': deviceId},
      );
      final body = res.data ?? const {};
      if (body['ok'] == true) {
        return FreeCoreSyncSuccess(
          active:    body['active'] == true,
          subUrl:    body['sub_url']?.toString(),
          plan:      body['plan']?.toString(),
          expiresAt: body['expires_at']?.toString(),
          servers:   _parseServers(body['servers']),
        );
      }
      return FreeCoreSyncError(body['error']?.toString() ?? 'unknown', httpStatus: res.statusCode);
    } on DioException catch (e) {
      return FreeCoreSyncError(_dioErrorCode(e), httpStatus: e.response?.statusCode);
    } catch (_) {
      return const FreeCoreSyncError('network');
    }
  }

  static List<FreeCoreServer> _parseServers(dynamic raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => FreeCoreServer(
              id:   e['id']?.toString()   ?? '',
              name: e['name']?.toString() ?? '',
              host: e['host']?.toString() ?? '',
            ))
        .where((s) => s.id.isNotEmpty)
        .toList();
  }

  static String _dioErrorCode(DioException e) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout => 'timeout',
      DioExceptionType.receiveTimeout    => 'timeout',
      DioExceptionType.sendTimeout       => 'timeout',
      DioExceptionType.connectionError   => 'no_network',
      _                                  => 'network',
    };
  }
}

class FreeCoreServer {
  const FreeCoreServer({required this.id, required this.name, required this.host});
  final String id;
  final String name;
  final String host;
}

sealed class FreeCoreRedeemResult {
  const FreeCoreRedeemResult();
}

class FreeCoreRedeemSuccess extends FreeCoreRedeemResult {
  const FreeCoreRedeemSuccess({
    required this.status,
    required this.subUrl,
    required this.plan,
    required this.expiresAt,
    required this.servers,
  });
  final String status;
  final String subUrl;
  final String plan;
  final String? expiresAt;
  final List<FreeCoreServer> servers;
}

class FreeCoreRedeemError extends FreeCoreRedeemResult {
  const FreeCoreRedeemError(this.code, {this.httpStatus});
  final String code;
  final int? httpStatus;
}

sealed class FreeCoreSyncResult {
  const FreeCoreSyncResult();
}

class FreeCoreSyncSuccess extends FreeCoreSyncResult {
  const FreeCoreSyncSuccess({
    required this.active,
    required this.subUrl,
    required this.plan,
    required this.expiresAt,
    required this.servers,
  });
  final bool active;
  final String? subUrl;
  final String? plan;
  final String? expiresAt;
  final List<FreeCoreServer> servers;
}

class FreeCoreSyncError extends FreeCoreSyncResult {
  const FreeCoreSyncError(this.code, {this.httpStatus});
  final String code;
  final int? httpStatus;
}
