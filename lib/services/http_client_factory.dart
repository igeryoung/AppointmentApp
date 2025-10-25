import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:flutter/foundation.dart';

/// Factory for creating HTTP clients with proper SSL certificate handling
class HttpClientFactory {
  /// Create an HTTP client with SSL certificate validation
  ///
  /// In debug mode: accepts self-signed certificates
  /// In production: strict certificate validation
  static http.Client createClient() {
    final ioClient = HttpClient();

    // Configure certificate validation
    ioClient.badCertificateCallback = (X509Certificate cert, String host, int port) {
      if (kDebugMode) {
        // Development: accept self-signed certificates
        debugPrint('⚠️  Accepting certificate for $host:$port (DEBUG MODE)');
        debugPrint('   Subject: ${cert.subject}');
        debugPrint('   Issuer: ${cert.issuer}');
        return true;
      } else {
        // Production: strict certificate validation
        debugPrint('❌ Invalid certificate rejected for $host:$port');
        debugPrint('   Subject: ${cert.subject}');
        return false;
      }
    };

    return IOClient(ioClient);
  }
}
