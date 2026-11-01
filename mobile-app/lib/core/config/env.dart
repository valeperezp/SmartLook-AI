import 'package:flutter/foundation.dart';

class Env {
  // Detección automática según plataforma:
  // - Web (Chrome / Edge): http://localhost:8000
  // - Emulador Android: http://10.0.2.2:8000
  // - Desktop / Otros: http://localhost:8000
  static String get apiUrl {
    if (kIsWeb) {
      return 'http://localhost:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'https://smartlook-ai-production.up.railway.app';
    }
    return 'http://localhost:8000';
  }

  static const String _webUrlOverride = String.fromEnvironment('WEB_URL', defaultValue: '');
  static String get webUrl {
    if (_webUrlOverride.isNotEmpty) return _webUrlOverride;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      // TODO: cuando se defina el deploy, compilar con
      // --dart-define=WEB_URL=https://tu-dominio.com
      return 'http://localhost:4200';
    }
    return 'http://localhost:4200';
  }
  static const String stripePublishableKey =
      'pk_test_51UGODfQ61dJbPxVzfUK66ISHzsuSMdEh5ghQ2LPhLXYj3XwYcj4nnf01uXI9ODLXW6uP76KthPxUw93pp8ZNwwHV00URCaL1zK';
  
  static const Duration timeout = Duration(seconds: 30);
}
