import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

enum SocketConnectionState { connecting, connected, disconnected }

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  // ----- Native WebSocket (Dewpoint Server) -----
  WebSocketChannel? _wsChannel;
  StreamSubscription? _wsSubscription;
  String? _wsUrl;
  String? _currentSubscribedCol;
  Timer? _wsReconnectTimer;

  final _dewpointController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get dewpointStream => _dewpointController.stream;

  final _wsStateController = StreamController<SocketConnectionState>.broadcast();
  Stream<SocketConnectionState> get wsStateStream => _wsStateController.stream;
  SocketConnectionState _wsState = SocketConnectionState.disconnected;
  SocketConnectionState get wsState => _wsState;

  // ----- Socket.IO (Gauge Server / Raspberry Pi) -----
  IO.Socket? _ioSocket;
  String? _ioUrl;
  
  final _gaugeController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get gaugeStream => _gaugeController.stream;

  final _ioStatusController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStatus => _ioStatusController.stream;
  bool _ioConnected = false;

  // ---------------------------------------------------------------------------
  // Native WebSocket Methods (Dewpoint)
  // ---------------------------------------------------------------------------
  
  void connectDewpoint(String url) {
    if (_wsUrl == url && _wsState != SocketConnectionState.disconnected) return;
    _wsUrl = url;
    _wsReconnect();
  }

  void _wsReconnect() {
    _wsReconnectTimer?.cancel();
    _closeWsInternal();
    
    _updateWsState(SocketConnectionState.connecting);
    print("[WS-DEW] Connecting to $_wsUrl...");

    try {
      _wsChannel = IOWebSocketChannel.connect(Uri.parse(_wsUrl!));
      _wsSubscription = _wsChannel!.stream.listen(
        (data) => _handleWsData(data),
        onDone: () => _handleWsDisconnect(),
        onError: (err) => _handleWsError(err),
      );
      // Assume connected for sending (buffering handled by channel)
      _updateWsState(SocketConnectionState.connected);
      
      // AUTO-RESUBSCRIBE: Restore active subscription immediately
      if (_currentSubscribedCol != null) {
        print("[WS-DEW] Restoring subscription for $_currentSubscribedCol");
        subscribeDewpoint(_currentSubscribedCol!);
      }
    } catch (e) {
      _handleWsError(e);
    }
  }

  void _handleWsData(dynamic data) {
    if (_wsState != SocketConnectionState.connected) {
      _updateWsState(SocketConnectionState.connected);
      print("[WS-DEW] Receiving data");
    }
    try {
      Map<String, dynamic> msg;
      if (data is Map) {
        msg = Map<String, dynamic>.from(data);
      } else if (data is String) {
        msg = jsonDecode(data);
      } else {
        // Fallback for unexpected types
        msg = jsonDecode(data.toString());
      }
      _dewpointController.add(msg);
    } catch (e) {
      print("[WS-DEW] Data parse error: $e. Raw data: $data (Type: ${data.runtimeType})");
    }
  }

  void _handleWsDisconnect() {
    print("[WS-DEW] Disconnected from server");
    _updateWsState(SocketConnectionState.disconnected);
    _scheduleWsReconnect();
  }

  void _handleWsError(dynamic err) {
    print("[WS-DEW] Error: $err");
    _updateWsState(SocketConnectionState.disconnected);
    _scheduleWsReconnect();
  }

  void _scheduleWsReconnect() {
    _wsReconnectTimer?.cancel();
    _wsReconnectTimer = Timer(const Duration(seconds: 3), () => _wsReconnect());
  }

  void _updateWsState(SocketConnectionState newState) {
    _wsState = newState;
    _wsStateController.add(newState);
  }

  void subscribeDewpoint(String col) {
    _currentSubscribedCol = col;
    print("[WS-DEW] Sending subscribe for $col");
    _sendWs({'action': 'subscribe', 'col': col});
  }

  void unsubscribeDewpoint(String col) {
    if (_currentSubscribedCol == col) _currentSubscribedCol = null;
    if (_wsState == SocketConnectionState.connected) {
      _sendWs({'action': 'unsubscribe', 'col': col});
    }
  }

  void _sendWs(Map<String, dynamic> msg) {
    try {
      _wsChannel?.sink.add(jsonEncode(msg));
    } catch (e) {
      print("[WS-DEW] Send error: $e");
    }
  }

  void _closeWsInternal() {
    _wsSubscription?.cancel();
    try { _wsChannel?.sink.close(); } catch (_) {}
    _wsChannel = null;
    _wsSubscription = null;
  }

  // ---------------------------------------------------------------------------
  // Socket.IO Methods (Gauge)
  // ---------------------------------------------------------------------------

  void connect(String url) {
    if (_ioSocket != null && _ioConnected && _ioUrl == url) {
        _ioStatusController.add(true);
        return;
    }
    if (_ioSocket != null) disconnect();
    
    _ioUrl = url;
    print("[IO-GAUGE] Connecting to $url...");

    _ioSocket = IO.io(
      url,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .enableAutoConnect()
          .build(),
    );

    _ioSocket!.onConnect((_) {
      print("[IO-GAUGE] Connected");
      _ioConnected = true;
      _ioStatusController.add(true);
    });

    _ioSocket!.onDisconnect((_) {
      print("[IO-GAUGE] Disconnected");
      _ioConnected = false;
      _ioStatusController.add(false);
    });

    _ioSocket!.onConnectError((err) {
      print("[IO-GAUGE] Error: $err");
      _ioConnected = false;
      _ioStatusController.add(false);
    });

    // Restore listeners
    _ioSocket!.on("height_update", (data) {
      if (data is Map && data.containsKey('value')) {
        _gaugeController.add({'height': data['value']});
      }
    });

    _ioSocket!.on("weight_update", (data) {
      if (data is Map && data.containsKey('value')) {
        _gaugeController.add({'weight': data['value']});
      }
    });

    _ioSocket!.on("pi_health_update", (data) {
      if (data is Map) {
        _gaugeController.add({
          'pi_temp': data['temp_c'], 
          'pi_throttled': data['throttled']
        });
      }
    });

    _ioSocket!.on("gauge_update", (data) {
      if (data is Map) {
        _gaugeController.add(Map<String, dynamic>.from(data));
      }
    });

    _ioSocket!.connect();
  }

  void disconnect() {
    try {
      _ioSocket?.disconnect();
    } catch (_) {}
    _ioConnected = false;
    _ioStatusController.add(false);
    _ioSocket = null;
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  void dispose() {
    _wsReconnectTimer?.cancel();
    _closeWsInternal();
    disconnect();
    _dewpointController.close();
    _wsStateController.close();
    _gaugeController.close();
    _ioStatusController.close();
  }
}
