import 'dart:async';
import 'dart:io';

/// Streams into a temporary file; only a complete response is published.
Future<int?> downloadMedia(String url, File target, int maxBytes) async {
  final http = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  final partial = File('${target.path}.part');
  RandomAccessFile? sink;
  try {
    if (maxBytes <= 0) return null;
    final response = await (await http.getUrl(Uri.parse(url)))
        .close()
        .timeout(const Duration(seconds: 30));
    final checkLength =
        response.compressionState !=
        HttpClientResponseCompressionState.decompressed;
    if (response.statusCode != HttpStatus.ok ||
        (checkLength && response.contentLength > maxBytes)) {
      return null;
    }
    sink = await partial.open(mode: FileMode.write);
    var bytes = 0;
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      bytes += chunk.length;
      if (bytes > maxBytes) return null;
      await sink.writeFrom(chunk);
    }
    await sink.close();
    sink = null;
    if (bytes == 0 ||
        (checkLength &&
            response.contentLength >= 0 &&
            bytes != response.contentLength)) {
      return null;
    }
    await partial.rename(target.path);
    return bytes;
  } on Exception {
    return null;
  } finally {
    http.close(force: true);
    await sink?.close();
    if (await partial.exists()) await partial.delete();
  }
}
