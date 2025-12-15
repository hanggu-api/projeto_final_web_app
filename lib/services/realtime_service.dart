import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api_service.dart';

class RealtimeService {
  static final RealtimeService _instance = RealtimeService._internal();
  factory RealtimeService() => _instance;
  RealtimeService._internal();

  io.Socket? _socket;

  void connect() {
    if (_socket != null) return;
    final base = ApiService.baseUrl;
    final url = base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
    _socket = io.io(url, io.OptionBuilder()
        .disableAutoConnect()
        .build());
    _socket!.connect();
  }

  void on(String event, Function(dynamic data) handler) {
    _socket?.on(event, (data) => handler(data));
  }

  void joinService(String serviceId) {
    _socket?.emit('join:service', serviceId);
  }

  void dispose() {
    _socket?.dispose();
    _socket = null;
  }
}