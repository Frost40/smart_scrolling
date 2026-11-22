import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/data/services/media_download_service.dart';

void main() {
  test('only a complete bounded response becomes a downloaded file', () async {
    final dir = await Directory.systemTemp.createTemp('media-test');
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/broken') {
        final socket = await request.response.detachSocket(writeHeaders: false);
        socket.write(
          'HTTP/1.1 200 OK\r\nContent-Length: 20\r\nConnection: close\r\n\r\nab',
        );
        await socket.flush();
        await socket.close();
      } else if (request.uri.path == '/gzip') {
        final bytes = gzip.encode(List.filled(10, 1));
        request.response.headers.set(HttpHeaders.contentEncodingHeader, 'gzip');
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      } else {
        request.response.add(List.filled(10, 1));
        await request.response.close();
      }
    });
    final file = File('${dir.path}/download');
    final base = 'http://127.0.0.1:${server.port}';
    try {
      expect(await downloadMedia('$base/ok', file, 10), 10);
      expect(await file.length(), 10);
      await file.delete();
      expect(await downloadMedia('$base/large', file, 9), isNull);
      expect(await file.exists(), false);
      expect(await downloadMedia('$base/broken', file, 100), isNull);
      expect(await file.exists(), false);
      expect(await File('${file.path}.part').exists(), false);
      expect(await downloadMedia('$base/gzip', file, 10), 10);
      expect(await file.readAsBytes(), List.filled(10, 1));
    } finally {
      await server.close(force: true);
      await dir.delete(recursive: true);
    }
  });
}
