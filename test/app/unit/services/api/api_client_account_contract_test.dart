@Tags(['unit'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:schedule_note_app/services/api_client.dart';

void main() {
  test(
    'API-CLIENT-ACCOUNT-001: registerAccount posts account payload',
    () async {
      final requests = <HttpRequest>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add(request);
        final body = await utf8.decoder.bind(request).join();
        final payload = jsonDecode(body) as Map<String, dynamic>;
        expect(payload['username'], 'alice');
        expect(payload['password'], 'password123');
        expect(payload['registrationPassword'], 'server-secret');
        expect(payload['deviceName'], 'iOS Device');
        expect(payload['platform'], 'ios');

        request.response.statusCode = 200;
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'success': true,
            'accountId': 'account-1',
            'username': 'alice',
            'deviceId': 'device-1',
            'deviceToken': 'token-1',
            'deviceRole': 'read',
          }),
        );
        await request.response.close();
      });

      final apiClient = ApiClient(
        baseUrl: 'http://${server.address.address}:${server.port}',
      );

      try {
        final response = await apiClient.registerAccount(
          username: 'alice',
          password: 'password123',
          registrationPassword: 'server-secret',
          deviceName: 'iOS Device',
          platform: 'ios',
        );

        expect(requests.single.method, 'POST');
        expect(requests.single.uri.path, '/api/accounts/register');
        expect(response['accountId'], 'account-1');
        expect(response['deviceId'], 'device-1');
      } finally {
        apiClient.dispose();
        await server.close(force: true);
      }
    },
  );

  test('API-CLIENT-ACCOUNT-002: loginAccount posts login payload', () async {
    final requests = <HttpRequest>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      requests.add(request);
      final body = await utf8.decoder.bind(request).join();
      final payload = jsonDecode(body) as Map<String, dynamic>;
      expect(payload['username'], 'alice');
      expect(payload['password'], 'password123');
      expect(payload.containsKey('registrationPassword'), isFalse);

      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'success': true,
          'accountId': 'account-1',
          'username': 'alice',
          'deviceId': 'device-2',
          'deviceToken': 'token-2',
          'deviceRole': 'read',
        }),
      );
      await request.response.close();
    });

    final apiClient = ApiClient(
      baseUrl: 'http://${server.address.address}:${server.port}',
    );

    try {
      final response = await apiClient.loginAccount(
        username: 'alice',
        password: 'password123',
        deviceName: 'iOS Device',
        platform: 'ios',
      );

      expect(requests.single.method, 'POST');
      expect(requests.single.uri.path, '/api/accounts/login');
      expect(response['deviceId'], 'device-2');
    } finally {
      apiClient.dispose();
      await server.close(force: true);
    }
  });
}
