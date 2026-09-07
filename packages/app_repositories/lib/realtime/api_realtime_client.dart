import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import '../api/api_client.dart';

enum RealtimeConnectionStatus {
  disconnected,
  connecting,
  connected,
  authenticationRequired,
}

class RealtimeDomainEvent {
  const RealtimeDomainEvent({
    required this.type,
    required this.aggregateType,
    required this.aggregateId,
    required this.data,
    required this.occurredAt,
  });

  final String type;
  final String aggregateType;
  final String aggregateId;
  final Map<String, dynamic> data;
  final DateTime occurredAt;

  static RealtimeDomainEvent? tryParse(Object? value) {
    if (value is! Map) return null;
    final json = Map<String, dynamic>.from(value);
    final type = json['type'];
    final aggregateType = json['aggregateType'];
    final aggregateId = json['aggregateId'];
    final occurredAt = DateTime.tryParse(json['occurredAt']?.toString() ?? '');
    final rawData = json['data'];
    if (type is! String ||
        aggregateType is! String ||
        aggregateId is! String ||
        occurredAt == null ||
        rawData is! Map) {
      return null;
    }
    return RealtimeDomainEvent(
      type: type,
      aggregateType: aggregateType,
      aggregateId: aggregateId,
      data: Map<String, dynamic>.from(rawData),
      occurredAt: occurredAt.toUtc(),
    );
  }
}

class RealtimeException implements Exception {
  const RealtimeException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'RealtimeException($code, $message)';
}

/// Authenticated Socket.IO client for the Nest realtime gateway.
///
/// One instance is owned by [NestRepositoryBundle]. It uses websocket-only
/// transport on Flutter, bounded exponential reconnection, a single explicit
/// refresh-token retry after an auth rejection, and typed domain events.
class ApiRealtimeClient {
  ApiRealtimeClient(
    this._client, {
    Duration connectionTimeout = const Duration(seconds: 12),
  })  : connectionTimeout = connectionTimeout,
        endpoint = realtimeEndpointFromApi(_client.baseUrl);

  final ApiClient _client;
  final Uri endpoint;
  final Duration connectionTimeout;
  final StreamController<RealtimeDomainEvent> _events =
      StreamController.broadcast();
  final StreamController<RealtimeConnectionStatus> _statuses =
      StreamController.broadcast();
  io.Socket? _socket;
  Future<void>? _connectInFlight;
  RealtimeConnectionStatus _status = RealtimeConnectionStatus.disconnected;
  bool _disposed = false;

  Stream<RealtimeDomainEvent> get events => _events.stream;
  Stream<RealtimeConnectionStatus> get statuses => _statuses.stream;
  RealtimeConnectionStatus get status => _status;

  Future<void> connect() {
    if (_disposed) {
      return Future.error(
        const RealtimeException('DISPOSED', 'Realtime client is closed.'),
      );
    }
    if (_status == RealtimeConnectionStatus.connected) {
      return Future.value();
    }
    return _connectInFlight ??= _connectWithRefresh().whenComplete(() {
      _connectInFlight = null;
    });
  }

  Future<void> _connectWithRefresh() async {
    try {
      await _connectOnce();
    } on RealtimeException catch (error) {
      if (error.code != 'INVALID_ACCESS_TOKEN') rethrow;
      final refreshed = await _client.refreshSession();
      if (!refreshed) {
        _disposeSocket();
        _setStatus(RealtimeConnectionStatus.authenticationRequired);
        rethrow;
      }
      await _connectOnce();
    }
  }

  Future<void> _connectOnce() async {
    final tokens = await _client.tokenStore.read();
    if (tokens == null) {
      _setStatus(RealtimeConnectionStatus.authenticationRequired);
      throw const RealtimeException(
        'NO_SESSION',
        'A signed-in session is required for realtime updates.',
      );
    }

    _disposeSocket();
    _setStatus(RealtimeConnectionStatus.connecting);
    final completer = Completer<void>();
    final socket = io.io(
      endpoint.toString(),
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .enableForceNew()
          .enableReconnection()
          .setReconnectionAttempts(8)
          .setReconnectionDelay(500)
          .setReconnectionDelayMax(10000)
          .setRandomizationFactor(0.5)
          .setTimeout(connectionTimeout.inMilliseconds)
          .setAuth({'token': tokens.accessToken})
          .build(),
    );
    _socket = socket;

    socket.on('ready', (_) {
      _setStatus(RealtimeConnectionStatus.connected);
      if (!completer.isCompleted) completer.complete();
    });
    socket.on('domain.event', (value) {
      final event = RealtimeDomainEvent.tryParse(value);
      if (event != null && !_events.isClosed) _events.add(event);
    });
    socket.on('auth.error', (_) {
      if (!completer.isCompleted) {
        completer.completeError(
          const RealtimeException(
            'INVALID_ACCESS_TOKEN',
            'The realtime access token was rejected.',
          ),
        );
      }
    });
    socket.onConnectError((Object? error) {
      if (!completer.isCompleted) {
        completer.completeError(
          RealtimeException(
            'CONNECTION_FAILED',
            error?.toString() ?? 'Realtime connection failed.',
          ),
        );
      }
    });
    socket.onDisconnect((_) {
      if (!_disposed) _setStatus(RealtimeConnectionStatus.disconnected);
    });
    socket.connect();

    try {
      await completer.future.timeout(connectionTimeout);
    } on TimeoutException {
      _disposeSocket();
      _setStatus(RealtimeConnectionStatus.disconnected);
      throw const RealtimeException(
        'CONNECTION_TIMEOUT',
        'Realtime connection timed out.',
      );
    }
  }

  void subscribeToPost(String submissionId) {
    _validateSubmissionId(submissionId);
    _requireConnected().emit('subscribe.post', {'submissionId': submissionId});
  }

  void unsubscribeFromPost(String submissionId) {
    _validateSubmissionId(submissionId);
    _requireConnected()
        .emit('unsubscribe.post', {'submissionId': submissionId});
  }

  io.Socket _requireConnected() {
    final socket = _socket;
    if (socket == null || _status != RealtimeConnectionStatus.connected) {
      throw const RealtimeException(
        'NOT_CONNECTED',
        'Realtime is not connected.',
      );
    }
    return socket;
  }

  void disconnect() {
    _disposeSocket();
    if (!_disposed) _setStatus(RealtimeConnectionStatus.disconnected);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _disposeSocket();
    _events.close();
    _statuses.close();
  }

  void _disposeSocket() {
    final socket = _socket;
    _socket = null;
    socket?.dispose();
  }

  void _setStatus(RealtimeConnectionStatus next) {
    if (_status == next) return;
    _status = next;
    if (!_statuses.isClosed) _statuses.add(next);
  }
}

/// Converts `https://host[/prefix]/api/v1` to the gateway namespace
/// `https://host[/prefix]/realtime` while preserving reverse-proxy prefixes.
Uri realtimeEndpointFromApi(Uri apiBaseUrl) {
  final segments = apiBaseUrl.pathSegments
      .where((segment) => segment.isNotEmpty)
      .toList(growable: true);
  if (segments.length >= 2 &&
      segments[segments.length - 2] == 'api' &&
      segments.last == 'v1') {
    segments.removeRange(segments.length - 2, segments.length);
  }
  segments.add('realtime');
  return apiBaseUrl.replace(
    pathSegments: segments,
    query: null,
    fragment: null,
  );
}

void _validateSubmissionId(String value) {
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value)) {
    throw ArgumentError.value(
      value,
      'submissionId',
      'must be a UUID',
    );
  }
}
