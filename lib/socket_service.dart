import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? socket;

  // Use a broadcast stream so multiple screens can listen if needed
  final _gaugeController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get gaugeStream => _gaugeController.stream;

  // Broadcast connection status
  final _connectionStatusController = StreamController<bool>.broadcast();
  Stream<bool> get connectionStatus => _connectionStatusController.stream;

  String? _currentUrl;

  void connect(String url) {
    // If we are already connected to *this* URL, do nothing.
    if (socket != null && socket!.connected && _currentUrl == url) {
        // Emit current status just in case
        _connectionStatusController.add(true);
        return;
    }

    // If connected to a different URL (or just a stale socket), disconnect first
    if (socket != null) {
      disconnect();
    }
    
    _currentUrl = url;

    socket = IO.io(
      url,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .build(),
    );

    socket!.onConnect((_) {
      print("[SOCKET] Connected to $url");
      _connectionStatusController.add(true);
    });

    // Debug: Listen to all events to verify event name
    socket!.onAny((event, data) {
       print("[SOCKET] Event: $event, Data: $data");
    });

    socket!.on("height_update", (data) {
      if (data is Map && data.containsKey('value')) {
        _gaugeController.add({'height': data['value']});
      }
    });

    socket!.on("weight_update", (data) {
      if (data is Map && data.containsKey('value')) {
        _gaugeController.add({'weight': data['value']});
      }
    });

    socket!.on("gauge_update", (data) {
      print("[SOCKET] gauge_update received: $data");
      if (data is Map) {
        // Add data to the stream
        _gaugeController.add(Map<String, dynamic>.from(data));
      }
    });

    socket!.onDisconnect((_) {
      print("[SOCKET] Disconnected");
      _connectionStatusController.add(false);
    });
    
    socket!.onConnectError((err) {
      print("[SOCKET] Error: $err");
      _connectionStatusController.add(false);
    });

    socket!.connect();
  }

  void disconnect() {
    try {
      socket?.disconnect();
    } catch (_) {}
    _connectionStatusController.add(false);
    socket = null;
  }
}
