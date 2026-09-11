import { Routes } from '@angular/router';
import { adminGuard } from './core/guards/admin.guard';
import { encargadoGuard } from './core/guards/encargado.guard';
import { proveedorGuard } from './core/guards/proveedor.guard';
import { guestGuard } from './core/guards/guest.guard';
import { homeGuard } from './core/guards/home.guard';
import { authGuard } from './core/guards/auth.guard';

export const routes: Routes = [
  {
    path: '',
    loadComponent: () => import('./features/home/home').then((m) => m.Home),
    canActivate: [homeGuard],
  },
  {
    path: 'login',
    loadComponent: () => import('./features/auth/login/login').then((m) => m.Login),
    canActivate: [guestGuard],
  },
  {
    path: 'registro',
    loadComponent: () => import('./features/auth/registro/registro').then((m) => m.Registro),
    canActivate: [guestGuard],
  },
  {
    path: 'mis-reservas',
    loadComponent: () =>
      import('./features/mis-reservas/mis-reservas').then((m) => m.MisReservas),
    canActivate: [authGuard],
  },
  {
    path: 'admin',
    loadComponent: () =>
      import('./features/admin/admin-layout/admin-layout').then((m) => m.AdminLayout),
    canActivate: [adminGuard],
    children: [
      {
        path: '',
        loadComponent: () =>
          import('./features/admin/admin-dashboard/admin-dashboard').then(
            (m) => m.AdminDashboard
          ),
      },
      {
        path: 'usuarios',
        loadComponent: () =>
          import('./features/admin/usuarios/usuarios-admin').then((m) => m.UsuariosAdmin),
      },
      {
        path: 'sucursales',
        loadComponent: () =>
          import('./features/admin/sucursales/sucursales-admin').then((m) => m.SucursalesAdmin),
      },
      {
        path: 'proveedores',
        loadComponent: () =>
          import('./features/admin/proveedores/proveedores-admin').then(
            (m) => m.ProveedoresAdmin
          ),
      },
      {
        path: 'inventario',
        loadComponent: () =>
          import('./features/admin/inventario/inventario-admin').then(
            (m) => m.InventarioAdmin
          ),
      },
      {
        path: 'catalogo/productos',
        loadComponent: () =>
          import('./features/admin/catalogo/productos/productos-admin').then(
            (m) => m.ProductosAdmin
          ),
      },
      {
        path: 'catalogo/categorias',
        loadComponent: () =>
          import('./features/admin/catalogo/categorias/categorias-admin').then(
            (m) => m.CategoriasAdmin
          ),
      },
      {
        path: 'catalogo/tallas',
        loadComponent: () =>
          import('./features/admin/catalogo/tallas/tallas-admin').then((m) => m.TallasAdmin),
      },
      {
        path: 'catalogo/colores',
        loadComponent: () =>
          import('./features/admin/catalogo/colores/colores-admin').then((m) => m.ColoresAdmin),
      },
      {
        path: 'catalogo/temporadas',
        loadComponent: () =>
          import('./features/admin/catalogo/temporadas/temporadas-admin').then(
            (m) => m.TemporadasAdmin
          ),
      },
      {
        path: 'catalogo/colecciones',
        loadComponent: () =>
          import('./features/admin/catalogo/colecciones/colecciones-admin').then(
            (m) => m.ColeccionesAdmin
          ),
      },
    ],
  },
  {
    path: 'encargado',
    loadComponent: () =>
      import('./features/encargado/encargado-layout/encargado-layout').then(
        (m) => m.EncargadoLayout
      ),
    canActivate: [encargadoGuard],
    children: [
      {
        path: '',
        loadComponent: () =>
          import('./features/encargado/encargado-dashboard/encargado-dashboard').then(
            (m) => m.EncargadoDashboard
          ),
      },
      {
        path: 'inventario',
        loadComponent: () =>
          import('./features/encargado/inventario/encargado-inventario').then(
            (m) => m.EncargadoInventario
          ),
      },
      {
        path: 'reservas',
        loadComponent: () =>
          import('./features/encargado/reservas/encargado-reservas').then(
            (m) => m.EncargadoReservas
          ),
      },
      {
        path: 'movimientos',
        loadComponent: () =>
          import('./features/encargado/movimientos/encargado-movimientos').then(
            (m) => m.EncargadoMovimientos
          ),
      },
    ],
  },
  {
    path: 'proveedor',
    loadComponent: () =>
      import('./features/proveedor/proveedor-layout/proveedor-layout').then(
        (m) => m.ProveedorLayout
      ),
    canActivate: [proveedorGuard],
    children: [
      {
        path: '',
        loadComponent: () =>
          import('./features/proveedor/proveedor-dashboard/proveedor-dashboard').then(
            (m) => m.ProveedorDashboard
          ),
      },
      {
        path: 'productos',
        loadComponent: () =>
          import('./features/proveedor/proveedor-productos/proveedor-productos').then(
            (m) => m.ProveedorProductos
          ),
      },
      {
        path: 'catalogo',
        loadComponent: () =>
          import('./features/proveedor/proveedor-catalogo/proveedor-catalogo').then(
            (m) => m.ProveedorCatalogo
          ),
      },
    ],
  },
];
