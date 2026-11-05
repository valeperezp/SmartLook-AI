import 'package:flutter/foundation.dart';

class Env {
  // Detección automática según plataforma:
  // - Web (Chrome / Edge): http://localhost:8000
  // - Emulador Android: http://10.0.2.2:8000
  // - Desktop / Otros: http://localhost:8000
  // Para apuntar la app a otro backend (p. ej. el local) sin tocar el código:
  //   flutter run --dart-define=API_URL=http://localhost:8001
  static const String _apiUrlOverride = String.fromEnvironment('API_URL', defaultValue: '');

  static String get apiUrl {
    if (_apiUrlOverride.isNotEmpty) return _apiUrlOverride;
    if (kIsWeb) {
      return 'http://localhost:8000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'https://smartlook-ai-production.up.railway.app';
    }
    return 'http://localhost:8000';
  }

  // URL pública del frontend web: la usa el QR secundario del pago, que se abre desde el teléfono del cliente.
  // En un celular `localhost` apuntaría al propio teléfono, así que en Android/iOS va la URL de producción
  // (provisional hasta definir el dominio real). En web/escritorio se usa el servidor de desarrollo.
  // Para cambiarla sin tocar el código: flutter run --dart-define=WEB_URL=https://tu-dominio.com
  static const String _webUrlOverride = String.fromEnvironment('WEB_URL', defaultValue: '');
  static const String _webUrlProduccion = 'https://smartlook-ai.vercel.app';

  static String get webUrl {
    if (_webUrlOverride.isNotEmpty) return _webUrlOverride;
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      return _webUrlProduccion;
    }
    return 'http://localhost:4200';
  }

  static const String stripePublishableKey =
      'pk_test_51UGODfQ61dJbPxVzfUK66ISHzsuSMdEh5ghQ2LPhLXYj3XwYcj4nnf01uXI9ODLXW6uP76KthPxUw93pp8ZNwwHV00URCaL1zK';
  
  static const Duration timeout = Duration(seconds: 30);
}
