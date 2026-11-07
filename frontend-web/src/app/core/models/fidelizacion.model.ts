/** CU17 — puntos de fidelización: saldo del cliente y la regla de su empresa (viene del backend). */
export interface MisPuntos {
  cliente_id: number;
  /** Puntos disponibles. */
  saldo: number;
  /** Cuánto descuenta cada punto, en centavos (regla de la empresa; por defecto 1000 = 10). */
  valor_punto_centavos: number;
  /** Lo que valen hoy todos sus puntos como descuento, en centavos. */
  valor_saldo_centavos: number;
}
