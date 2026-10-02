import 'dart:async';

import 'package:web_socket_channel/io.dart';

enum SocketStatus { connected, failed, closed }

class WebScoketUtils {
  SocketStatus status = SocketStatus.closed;

  /// 链接
  final String url;

  /// 备用链接
  final String? backupUrl;

  /// 心跳时间
  final int heartBeatTime;

  /// 接收到信息
  final Function(dynamic)? onMessage;

  /// 连接关闭
  final Function(String msg)? onClose;

  /// 尝试重连
  final Function()? onReconnect;

  /// 准备就绪
  final Function()? onReady;

  /// 心跳
  final Function()? onHeartBeat;

  /// 请求头
  Map<String, dynamic>? headers;
  WebScoketUtils({
    required this.url,
    required this.heartBeatTime,
    this.onMessage,
    this.onClose,
    this.onReconnect,
    this.onReady,
    this.onHeartBeat,
    this.headers,
    this.backupUrl,
  });
  IOWebSocketChannel? webSocket;
  Timer? heartBeatTimer;

  /// 重连次数
  int reconnectTime = 0;
  Timer? reconnectTimer;

  /// 最大重连次数
  int maxReconnectTime = 5;

  StreamSubscription<dynamic>? streamSubscription;
  int _generation = 0;
  bool _closed = true;

  void connect({bool retry = false}) async {
    close();
    _closed = false;
    final generation = _generation;
    try {
      var wsurl = url;
      if (backupUrl != null && backupUrl!.isNotEmpty && retry) {
        wsurl = backupUrl!;
      }
      final socket = IOWebSocketChannel.connect(
        wsurl,
        connectTimeout: Duration(seconds: 10),
        headers: headers,
      );
      webSocket = socket;
      await socket.ready;
      if (_closed || generation != _generation) {
        unawaited(socket.sink.close());
        return;
      }
      ready();
    } catch (e) {
      if (_closed || generation != _generation) return;
      if (!retry) {
        connect(retry: true);
        return;
      }
      onError(e, StackTrace.current);
    }
  }

  /// 连接完成
  void ready() {
    if (_closed) return;
    final generation = _generation;
    status = SocketStatus.connected;

    streamSubscription = webSocket?.stream.listen(
      (data) {
        if (!_closed && generation == _generation) receiveMessage(data);
      },
      onError: (Object e, StackTrace s) {
        if (!_closed && generation == _generation) onError(e, s);
      },
      onDone: () {
        if (!_closed && generation == _generation) onDone();
      },
    );

    onReady?.call();
    if (!_closed && generation == _generation) initHeartBeat();
  }

  void initHeartBeat() {
    heartBeatTimer?.cancel();
    if (_closed) return;
    final generation = _generation;
    heartBeatTimer = Timer.periodic(Duration(milliseconds: heartBeatTime), (
      timer,
    ) {
      if (!_closed && generation == _generation) onHeartBeat?.call();
    });
  }

  void receiveMessage(dynamic data) {
    //接受到一条信息才算重连成功
    reconnectTime = 0;
    onMessage?.call(data);
  }

  void onError(Object e, StackTrace s) {
    status = SocketStatus.failed;
    onClose?.call(e.toString());
  }

  void onDone() {
    if (_closed || status == SocketStatus.closed) {
      return;
    }
    onReconnect?.call();
    if (!_closed) reconnect();
  }

  void sendMessage(dynamic message) {
    if (status == SocketStatus.connected) {
      webSocket?.sink.add(message);
    }
  }

  void close() {
    _closed = true;
    _generation++;
    status = SocketStatus.closed;

    streamSubscription?.cancel();
    streamSubscription = null;

    reconnectTimer?.cancel();
    reconnectTimer = null;

    webSocket?.sink.close();
    webSocket = null;

    heartBeatTimer?.cancel();
    heartBeatTimer = null;
  }

  void reconnect() {
    if (_closed) return;
    heartBeatTimer?.cancel();
    heartBeatTimer = null;
    status = SocketStatus.closed;
    if (reconnectTime < maxReconnectTime) {
      reconnectTime++;
      final generation = _generation;
      reconnectTimer ??= Timer(Duration(seconds: 5), () {
        reconnectTimer = null;
        if (!_closed && generation == _generation) connect();
      });
    } else {
      onClose?.call("重连超过最大次数，与服务器断开连接");
      reconnectTimer?.cancel();
      reconnectTimer = null;
      close();
      return;
    }
  }
}
