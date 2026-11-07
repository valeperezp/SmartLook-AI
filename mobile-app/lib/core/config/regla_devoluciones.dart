import 'package:shared_preferences/shared_preferences.dart';

/// Plazo (en días) para cambios y devoluciones (CU11).
///
/// El que MANDA es el backend: él rechaza ("El plazo para cambios ha vencido") toda devolución fuera de plazo. Esta clase
/// solo guarda, para usarlo sin conexión, el plazo que el backend informó la última vez, y lo usa como ESTIMACIÓN para avisar
/// al cajero: nunca bloquea. [valorPorDefectoDias] rige hasta recibir el de la empresa.
class ReglaDevoluciones {
  ReglaDevoluciones._();

  static const int valorPorDefectoDias = 7;
  static const String _clave = 'regla_devoluciones.plazo_dias';

  static int _dias = valorPorDefectoDias;

  /// Plazo estimado, en días, desde la venta.
  static int get plazoDias => _dias;

  /// Aplica el plazo recibido del backend en memoria (valores no válidos se ignoran).
  static void establecer(int dias) {
    if (dias > 0) _dias = dias;
  }

  /// Aplica el plazo recibido del backend y lo guarda en el dispositivo.
  static Future<void> guardar(int dias) async {
    if (dias <= 0) return;
    _dias = dias;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_clave, dias);
    } catch (_) {
      // Sin almacenamiento disponible el plazo sigue valiendo en memoria durante esta sesión.
    }
  }

  /// Recupera el último plazo recibido del backend (al arrancar la app).
  static Future<void> cargarGuardada() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final dias = prefs.getInt(_clave);
      if (dias != null && dias > 0) _dias = dias;
    } catch (_) {
      // se queda con el valor que ya tenga
    }
  }

  /// Solo para pruebas: vuelve al valor por defecto.
  static void restablecer() => _dias = valorPorDefectoDias;
}
