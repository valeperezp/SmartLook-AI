import 'regla_puntos.dart';

/// Constantes de negocio del módulo offline (ajustables en un solo lugar).
class OfflineConfig {
  OfflineConfig._();

  /// Fidelización (CU17): centavos de gasto por cada punto. YA NO está fijo: lo define el backend por empresa (ver
  /// [ReglaPuntos]); 1000 (1 punto por cada $10) es solo el valor por defecto hasta recibir el de la empresa.
  static int get centavosPorPunto => ReglaPuntos.valorPuntoCentavos;

  /// Puntos que gana una compra de [totalCentavos] (se redondea hacia abajo).
  static int puntosPara(int totalCentavos) => ReglaPuntos.puntosPara(totalCentavos);

  /// Días que un aviso de stock queda pendiente antes de pasar a 'expirado' (CU16).
  static const int vigenciaSuscripcionDias = 60;
}
