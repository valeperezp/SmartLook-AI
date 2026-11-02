export interface ReservasPorEstado {
  estado: string;
  cantidad: number;
}

export interface ReservasPorSucursal {
  sucursal_id: number;
  nombre_sucursal: string;
  cantidad_reservas: number;
  total_unidades: number;
}

export interface ProductoMasReservado {
  producto_id: number;
  nombre_producto: string;
  nombre_categoria: string | null;
  total_unidades: number;
  total_reservas: number;
}

export interface ReservasPorDia {
  fecha: string;
  cantidad: number;
}

export interface ResumenReportes {
  total_reservas: number;
  total_unidades_reservadas: number;
  reservas_por_estado: ReservasPorEstado[];
  inventario_disponible: number;
  inventario_reservado: number;
  productos_stock_bajo: number;
  productos_agotados: number;
}

// ---------- Dashboard analítico (CU15) ----------

export interface ResumenVentas {
  cantidad_ventas: number;
  ingresos: number;
  ticket_promedio: number;
  unidades_vendidas: number;
  /** null cuando no hubo ventas en el período anterior */
  variacion_ingresos_pct: number | null;
}

export interface VentasPorDia {
  fecha: string;
  cantidad: number;
  ingresos: number;
}

export interface AlertaStockReporte {
  inventario_id: number;
  nombre_producto: string;
  nombre_sucursal: string;
  cantidad_disponible: number;
  stock_minimo: number;
  mensaje: string;
}

export interface Dashboard {
  periodo_dias: number;
  nombre_sucursal: string;
  ventas: ResumenVentas;
  ventas_por_dia: VentasPorDia[];
  ventas_por_sucursal: { sucursal_id: number; nombre_sucursal: string; cantidad_ventas: number; ingresos: number }[];
  ventas_por_categoria: { categoria: string; unidades: number; ingresos: number }[];
  ventas_por_canal: { canal: string; cantidad: number; ingresos: number }[];
  top_vendidos: { producto_id: number; nombre_producto: string; nombre_categoria: string | null; unidades: number; ingresos: number }[];
  resumen: ResumenReportes;
  reservas_por_dia: ReservasPorDia[];
  top_reservados: ProductoMasReservado[];
  alertas_stock: AlertaStockReporte[];
}

// ---------- Reporte generativo (CU14) ----------

export interface ReporteGenerativo {
  titulo: string;
  contenido: string;
  generado_con_ia: boolean;
  periodo_dias: number;
  nombre_sucursal: string;
  generado_en: string;
  sugerencias: string[];
}