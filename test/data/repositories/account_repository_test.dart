import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_scrolling/data/repositories/account_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test(
    'deletion keeps the confirming token when accounts change before dispatch',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = SupabaseClient(
        'http://127.0.0.1:${server.port}',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      );
      final request = server.first.then((r) async {
        final authorization = r.headers.value('Authorization');
        await r.drain<void>();
        r.response.statusCode = 204;
        await r.response.close();
        return authorization;
      });
      Future<void> signIn(String id) async {
        await client.auth.recoverSession(
          jsonEncode({
            'access_token': 'test-$id',
            'token_type': 'bearer',
            'user': {
              'id': id,
              'app_metadata': {},
              'user_metadata': {},
              'aud': 'authenticated',
              'created_at': '2026-10-31T00:00:00Z',
            },
          }),
        );
      }

      try {
        final repo = AccountRepository(client);
        expect(repo.deleteData, throwsStateError);
        await signIn('a');
        final deleting = repo.deleteData();
        await signIn('b');
        await deleting;
        expect(await request, 'Bearer test-a');
      } finally {
        await client.dispose();
        await server.close(force: true);
      }
    },
  );
}
