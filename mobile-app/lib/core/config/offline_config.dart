/// Constantes de negocio del módulo offline (ajustables en un solo lugar).
class OfflineConfig {
  OfflineConfig._();

  /// Fidelización (CU17): 1 punto por cada $10 gastados = 1000 centavos.
  static const int centavosPorPunto = 1000;

  /// Puntos que gana una compra de [totalCentavos] (se redondea hacia abajo).
  static int puntosPara(int totalCentavos) => totalCentavos ~/ centavosPorPunto;

  /// Días que un aviso de stock queda pendiente antes de pasar a 'expirado' (CU16).
  static const int vigenciaSuscripcionDias = 60;
}
