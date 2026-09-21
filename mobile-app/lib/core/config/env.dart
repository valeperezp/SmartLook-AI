class Env {
  // Emulador Android:
  static const String apiUrl = 'http://10.0.2.2:8000';
  // Web (Chrome): http://localhost:8000
  // Producción: https://smartlook-ai-production.up.railway.app
  // Celular físico: http://192.168.X.X:8000

  static const String webUrl = 'http://localhost:4200';
  static const String stripePublishableKey =
      'pk_test_51UGODfQ61dJbPxVzfUK66ISHzsuSMdEh5ghQ2LPhLXYj3XwYcj4nnf01uXI9ODLXW6uP76KthPxUw93pp8ZNwwHV00URCaL1zK';
  
  static const Duration timeout = Duration(seconds: 30);
}
