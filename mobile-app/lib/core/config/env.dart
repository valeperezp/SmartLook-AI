class Env {
  static const String apiUrl = 'http://localhost:8000';
  
  // Para emulador Android usa: 'http://10.0.2.2:8000'
  // Para celular físico usa: 'http://192.168.X.X:8000' (tu IP local)
  
  static const Duration timeout = Duration(seconds: 30);
}
