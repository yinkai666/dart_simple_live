import 'dart:async';
import 'dart:io';

import '../lib/src/common/web_socket_util.dart';

// Run with the app's resolved package configuration; no Flutter engine needed.
Future<void> main() async {
  await checkCloseDuringHandshake();
  await checkCloseFromReady();
}

Future<void> checkCloseDuringHandshake() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final requested = Completer<void>();
  final release = Completer<void>();
  final sockets = <WebSocket>[];
  server.listen((request) async {
    requested.complete();
    await release.future;
    sockets.add(await WebSocketTransformer.upgrade(request));
  });
  var readyCalls = 0;
  var heartbeats = 0;
  final client = WebScoketUtils(
    url: 'ws://127.0.0.1:${server.port}',
    heartBeatTime: 5,
    onReady: () => readyCalls++,
    onHeartBeat: () => heartbeats++,
  );
  try {
    client.connect();
    await requested.future.timeout(const Duration(seconds: 3));
    client.close();
    release.complete();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    if (readyCalls != 0 ||
        heartbeats != 0 ||
        client.status != SocketStatus.closed) {
      throw StateError(
        'Closed handshake revived: ready=$readyCalls, '
        'heartbeats=$heartbeats, status=${client.status}',
      );
    }
    print('PASS: close during handshake cannot revive socket or heartbeat');
  } finally {
    client.close();
    for (final socket in sockets) {
      unawaited(socket.close());
    }
    await server.close(force: true);
  }
}

Future<void> checkCloseFromReady() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final sockets = <WebSocket>[];
  server.listen((request) async {
    sockets.add(await WebSocketTransformer.upgrade(request));
  });
  final ready = Completer<void>();
  var heartbeats = 0;
  late WebScoketUtils client;
  client = WebScoketUtils(
    url: 'ws://127.0.0.1:${server.port}',
    heartBeatTime: 5,
    onReady: () {
      client.close();
      ready.complete();
    },
    onHeartBeat: () => heartbeats++,
  );
  try {
    client.connect();
    await ready.future.timeout(const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (heartbeats != 0 ||
        client.heartBeatTimer != null ||
        client.webSocket != null ||
        client.streamSubscription != null) {
      throw StateError('Closing from onReady retained socket resources');
    }
    print('PASS: close from onReady releases resources without a heartbeat');
  } finally {
    client.close();
    for (final socket in sockets) {
      unawaited(socket.close());
    }
    await server.close(force: true);
  }
}
