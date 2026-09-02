export interface Proveedor {
  id: number;
  nombre: string;
  contacto?: string;
  telefono?: string;
  email?: string;
  activo: boolean;
}

export interface ProveedorCreate {
  nombre: string;
  contacto?: string;
  telefono?: string;
  email?: string;
}
