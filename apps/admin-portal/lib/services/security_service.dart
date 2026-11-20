import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class SecurityService {
  // TLS pinning:
  //  - Root of trust = assets/certs/gtsr4.pem (Google Trust Services GTS Root
  //    R4) loaded into the SecurityContext — the strong, rotation-safe layer.
  //  - Leaf SHA-256 pins below are a second layer; Supabase rotates its leaf
  //    cert roughly every 3 months (current one expires ~2026-09-26). If all
  //    requests start failing with HandshakeException after a Supabase-side
  //    rotation, fetch the new leaf cert from https://<project>.supabase.co,
  //    compute its SHA-256 fingerprint and add it to this list.
  static const _pinnedSha256 = <String>[
    'e48907236038c7feb05cd862e41cd7fc5728f28da61b95e6761d9c295c5b3298',
    '1dfc1605fbad358d8bc844f76d15203fac9ca5c1a79fd4857ffaf2864fbebf96',
    '76b27b80a58027dc3cf1da68dac17010ed93997d0b603e2fadbe85012493b5a7',
  ];

  static Future<http.Client> createSecureHttpClient() async {
    if (kIsWeb) {
      return http.Client();
    }

    final pemBytes = await rootBundle.load('assets/certs/gtsr4.pem');
    final securityContext = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(pemBytes.buffer.asUint8List());
    final httpClient = HttpClient(context: securityContext)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) {
        if (!_isSupabaseHost(host)) {
          return false;
        }

        try {
          final der = _pemToDer(cert.pem);
          final hash = sha256.convert(der).toString();
          return _pinnedSha256.contains(hash);
        } catch (_) {
          return false;
        }
      };

    return IOClient(httpClient);
  }

  static bool _isSupabaseHost(String host) {
    return host.endsWith('.supabase.co') || host == 'supabase.co';
  }

  static List<int> _pemToDer(String pem) {
    final b64 = pem
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .replaceAll(RegExp(r'\s'), '');
    return base64Decode(b64);
  }
}
