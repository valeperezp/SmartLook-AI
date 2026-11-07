import 'package:shared_preferences/shared_preferences.dart';

/// Regla de fidelización (CU17) de la empresa: cuánto vale un punto.
///
/// El valor lo define el BACKEND por empresa (multi-tenant): la app lo descarga (`/clientes/mis-puntos` o
/// `/clientes/regla-puntos`), lo guarda en el dispositivo para poder usarlo sin conexión y solo recurre a
/// [valorPorDefectoCentavos] si todavía nunca lo recibió.
///
/// Es el mismo número para las dos direcciones: gastar [valorPuntoCentavos] da 1 punto, y 1 punto canjeado
/// descuenta [valorPuntoCentavos].
class ReglaPuntos {
  ReglaPuntos._();

  /// Valor por defecto del backend (1000 centavos = 1 punto por cada 10 Bs). Solo se usa hasta recibir el real.
  static const int valorPorDefectoCentavos = 1000;
  static const String _clave = 'regla_puntos.valor_punto_centavos';

  static int _valor = valorPorDefectoCentavos;

  /// Cuánto vale un punto, en centavos.
  static int get valorPuntoCentavos => _valor;

  /// Puntos que gana una compra de [totalCentavos] (se redondea hacia abajo).
  static int puntosPara(int totalCentavos) => totalCentavos <= 0 ? 0 : totalCentavos ~/ _valor;

  /// Descuento (en centavos) que dan [puntos] al canjearlos.
  static int descuentoCentavos(int puntos) => puntos <= 0 ? 0 : puntos * _valor;

  /// Cuántos puntos se pueden canjear en una compra de [totalCentavos]: todos los que tiene ([saldo]) sin que el
  /// descuento supere el total.
  static int puntosUsables({required int saldo, required int totalCentavos}) {
    if (saldo <= 0 || totalCentavos <= 0) return 0;
    final topePorTotal = totalCentavos ~/ _valor;
    return saldo < topePorTotal ? saldo : topePorTotal;
  }

  /// Aplica la regla recibida del backend en memoria (valores no válidos se ignoran).
  static void establecer(int valorPuntoCentavos) {
    if (valorPuntoCentavos > 0) _valor = valorPuntoCentavos;
  }

  /// Aplica la regla recibida del backend y la guarda en el dispositivo para usarla sin conexión.
  static Future<void> guardar(int valorPuntoCentavos) async {
    if (valorPuntoCentavos <= 0) return;
    _valor = valorPuntoCentavos;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_clave, valorPuntoCentavos);
    } catch (_) {
      // Sin almacenamiento disponible la regla sigue valiendo en memoria durante esta sesión.
    }
  }

  /// Recupera la última regla recibida del backend (al arrancar la app).
  static Future<void> cargarGuardada() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final valor = prefs.getInt(_clave);
      if (valor != null && valor > 0) _valor = valor;
    } catch (_) {
      // se queda con el valor que ya tenga
    }
  }

  /// Solo para pruebas: vuelve al valor por defecto.
  static void restablecer() => _valor = valorPorDefectoCentavos;
}
