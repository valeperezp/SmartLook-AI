export interface SucursalQR {
  id: number;
  sucursal_id: number;
  imagen_path: string;
  activo: boolean;
  creado_en: string;
  desactivado_en: string | null;
  imagen_url: string;
}
