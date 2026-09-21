import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/admin/screens/admin_inventario_screen.dart';
import '../../features/admin/screens/admin_productos_screen.dart';
import '../../features/admin/screens/admin_usuarios_screen.dart';
import '../../features/admin/reportes/screens/reportes_screen.dart';
import '../../features/admin/promociones/models/promocion.dart';
import '../../features/admin/promociones/screens/promociones_screen.dart';
import '../../features/admin/promociones/screens/promocion_form_screen.dart';
import '../../features/admin/ia_config/screens/ia_config_screen.dart';
import '../../features/admin/sucursales/screens/sucursales_screen.dart';
import '../../features/admin/sucursales/screens/sucursal_form_screen.dart';
import '../models/sucursal.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/registro_screen.dart';
import '../../features/catalogo/screens/home_screen.dart';
import '../../features/encargado/screens/encargado_dashboard_screen.dart';
import '../../features/encargado/screens/encargado_inventario_screen.dart';
import '../../features/encargado/screens/encargado_reservas_screen.dart';
import '../../features/encargado/ventas/screens/ventas_sucursal_screen.dart';
import '../../features/encargado/pagos_pendientes/screens/pagos_pendientes_screen.dart';
import '../../features/encargado/mi_qr/screens/mi_qr_screen.dart';
import '../../features/encargado/movimientos/screens/movimientos_screen.dart';
import '../../features/cajero/screens/cajero_dashboard_screen.dart';
import '../../features/cajero/pos/screens/pos_screen.dart';
import '../../features/cajero/ventas/screens/mis_ventas_screen.dart';
import '../../features/cajero/qr/screens/qr_cajero_screen.dart';
import '../../features/carrito/screens/carrito_screen.dart';
import '../../features/checkout/screens/checkout_screen.dart';
import '../../features/mis_compras/screens/mis_compras_screen.dart';
import '../../features/proveedor/screens/proveedor_catalogo_screen.dart';
import '../../features/proveedor/screens/proveedor_dashboard_screen.dart';
import '../../features/proveedor/screens/proveedor_productos_screen.dart';
import '../../features/reservas/screens/mis_reservas_screen.dart';
import '../../features/vestidor/screens/vestidor_screen.dart';

class MainShellScreen extends StatelessWidget {
  final Widget child;

  const MainShellScreen({super.key, required this.child});

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/mis-reservas')) return 1;
    if (location.startsWith('/mis-compras')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _calculateSelectedIndex(context);

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          if (index == 0) {
            context.go('/');
          } else if (index == 1) {
            context.go('/mis-reservas');
          } else if (index == 2) {
            context.go('/mis-compras');
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Catálogo',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Mis Reservas',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(Icons.shopping_bag),
            label: 'Mis Compras',
          ),
        ],
      ),
    );
  }
}

class EncargadoPlaceholderScreen extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const EncargadoPlaceholderScreen({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.orange.shade800,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/encargado'),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: Colors.orange.shade400),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange.shade800,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => context.go('/encargado'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver al panel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ProveedorPlaceholderScreen extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;

  const ProveedorPlaceholderScreen({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal.shade800,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/proveedor'),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 64, color: Colors.teal.shade400),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 15),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade800,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => context.go('/proveedor'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver al panel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Temporizador de seguridad: tras máximo 4 segundos forzar que el router avance
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) {
          final auth = context.read<AuthProvider>();
          if (!auth.isInitialized) {
            auth.forzarInicializacion();
          }
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2563EB),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/splash_logo.png',
              width: 120,
              height: 120,
            ),
            const SizedBox(height: 24),
            const Text(
              'SmartLook AI',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Moda Inteligente a tu Medida',
              style: TextStyle(
                fontSize: 14,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

class AppRouter {
  final AuthProvider authProvider;
  late final GoRouter router;

  AppRouter(this.authProvider) {
    router = GoRouter(
      initialLocation: '/splash',
      refreshListenable: authProvider,
      redirect: (BuildContext context, GoRouterState state) {
        final location = state.matchedLocation;

        if (!authProvider.isInitialized) {
          return location == '/splash' ? null : '/splash';
        }

        final isLoggedIn = authProvider.isLoggedIn;
        final isAuthRoute =
            location == '/login' || location == '/registro';

        // 1. Si NO está logueado
        if (!isLoggedIn) {
          return isAuthRoute ? null : '/login';
        }

        // 2. Si SÍ está logueado
        final rol = authProvider.usuario?.rol ?? 'cliente';

        if (rol == 'proveedor') {
          // Proveedor intentando entrar a login, registro, splash o rutas cliente/admin/encargado/cajero
          if (isAuthRoute ||
              location == '/' ||
              location == '/splash' ||
              location == '/mis-reservas' ||
              location == '/mis-compras' ||
              location == '/carrito' ||
              location == '/checkout' ||
              location == '/vestidor' ||
              location.startsWith('/admin') ||
              location.startsWith('/encargado') ||
              location.startsWith('/cajero')) {
            return '/proveedor';
          }
          return null;
        } else if (rol == 'encargado_sucursal') {
          // Encargado intentando entrar a login, registro, splash o rutas cliente/admin/proveedor/cajero
          if (isAuthRoute ||
              location == '/' ||
              location == '/splash' ||
              location == '/mis-reservas' ||
              location == '/mis-compras' ||
              location == '/carrito' ||
              location == '/checkout' ||
              location == '/vestidor' ||
              location.startsWith('/admin') ||
              location.startsWith('/proveedor') ||
              location.startsWith('/cajero')) {
            return '/encargado';
          }
          return null;
        } else if (rol == 'cajero') {
          // Cajero intentando entrar a login, registro, splash o rutas cliente/admin/encargado/proveedor
          if (isAuthRoute ||
              location == '/' ||
              location == '/splash' ||
              location == '/mis-reservas' ||
              location == '/mis-compras' ||
              location == '/carrito' ||
              location == '/checkout' ||
              location == '/vestidor' ||
              location.startsWith('/admin') ||
              location.startsWith('/encargado') ||
              location.startsWith('/proveedor')) {
            return '/cajero';
          }
          return null;
        } else if (rol == 'administrador') {
          // Admin intentando entrar a login, registro, splash o rutas cliente/encargado/proveedor/cajero
          if (isAuthRoute ||
              location == '/' ||
              location == '/splash' ||
              location == '/mis-reservas' ||
              location == '/mis-compras' ||
              location == '/carrito' ||
              location == '/checkout' ||
              location == '/vestidor' ||
              location.startsWith('/encargado') ||
              location.startsWith('/proveedor') ||
              location.startsWith('/cajero')) {
            return '/admin';
          }
          return null;
        } else {
          // Cliente intentando entrar a login, registro, splash o rutas admin/encargado/proveedor/cajero
          if (isAuthRoute ||
              location == '/splash' ||
              location.startsWith('/admin') ||
              location.startsWith('/encargado') ||
              location.startsWith('/proveedor') ||
              location.startsWith('/cajero')) {
            return '/';
          }
          return null;
        }
      },
      routes: [
        GoRoute(
          path: '/splash',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const SplashScreen(),
          ),
        ),
        // Rutas Cliente con ShellRoute (Tabs inferiores)
        ShellRoute(
          builder: (context, state, child) => MainShellScreen(child: child),
          routes: [
            GoRoute(
              path: '/',
              pageBuilder: (context, state) => _buildFadeTransitionPage(
                state: state,
                child: const HomeScreen(),
              ),
            ),
            GoRoute(
              path: '/mis-reservas',
              pageBuilder: (context, state) => _buildFadeTransitionPage(
                state: state,
                child: const MisReservasScreen(),
              ),
            ),
            GoRoute(
              path: '/mis-compras',
              pageBuilder: (context, state) => _buildFadeTransitionPage(
                state: state,
                child: const MisComprasScreen(),
              ),
            ),
          ],
        ),

        // Ruta Carrito (Cliente)
        GoRoute(
          path: '/carrito',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const CarritoScreen(),
          ),
        ),

        // Ruta Checkout (Cliente)
        GoRoute(
          path: '/checkout',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const CheckoutScreen(),
          ),
        ),

        // Ruta Vestidor Virtual 3D/AR (Cliente)
        GoRoute(
          path: '/vestidor',
          pageBuilder: (context, state) {
            final param = state.uri.queryParameters['productoId'];
            final id = param != null ? int.tryParse(param) : null;
            return _buildFadeTransitionPage(
              state: state,
              child: VestidorScreen(productoId: id),
            );
          },
        ),

        // Rutas Admin
        GoRoute(
          path: '/admin',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const AdminDashboardScreen(),
          ),
        ),
        GoRoute(
          path: '/admin/usuarios',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const AdminUsuariosScreen(),
          ),
        ),
        GoRoute(
          path: '/admin/productos',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const AdminProductosScreen(),
          ),
        ),
        GoRoute(
          path: '/admin/inventario',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const AdminInventarioScreen(),
          ),
        ),
        GoRoute(
          path: '/admin/reportes',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const ReportesScreen(),
          ),
        ),
        GoRoute(
          path: '/admin/promociones',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const PromocionesScreen(),
          ),
        ),
        GoRoute(
          path: '/admin/promociones/form',
          pageBuilder: (context, state) {
            final promo = state.extra as Promocion?;
            return _buildFadeTransitionPage(
              state: state,
              child: PromocionFormScreen(promocion: promo),
            );
          },
        ),
        GoRoute(
          path: '/admin/ia-config',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const IaConfigScreen(),
          ),
        ),
        GoRoute(
          path: '/admin/sucursales',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const SucursalesScreen(),
          ),
        ),
        GoRoute(
          path: '/admin/sucursales/form',
          pageBuilder: (context, state) {
            final sucursal = state.extra as Sucursal?;
            return _buildFadeTransitionPage(
              state: state,
              child: SucursalFormScreen(sucursal: sucursal),
            );
          },
        ),

        // Rutas Encargado
        GoRoute(
          path: '/encargado',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const EncargadoDashboardScreen(),
          ),
        ),
        GoRoute(
          path: '/encargado/inventario',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const EncargadoInventarioScreen(),
          ),
        ),
        GoRoute(
          path: '/encargado/movimientos',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const MovimientosScreen(),
          ),
        ),
        GoRoute(
          path: '/encargado/reservas',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const EncargadoReservasScreen(),
          ),
        ),
        GoRoute(
          path: '/encargado/ventas',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const VentasSucursalScreen(),
          ),
        ),
        GoRoute(
          path: '/encargado/pagos-pendientes',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const PagosPendientesScreen(),
          ),
        ),
        GoRoute(
          path: '/encargado/mi-qr',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const MiQrScreen(),
          ),
        ),

        // Rutas Cajero
        GoRoute(
          path: '/cajero',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const CajeroDashboardScreen(),
          ),
        ),
        GoRoute(
          path: '/cajero/pos',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const PosScreen(),
          ),
        ),
        GoRoute(
          path: '/cajero/mis-ventas',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const MisVentasScreen(),
          ),
        ),
        GoRoute(
          path: '/cajero/qr',
          pageBuilder: (context, state) {
            final vParam = state.uri.queryParameters['ventaId'];
            final mParam = state.uri.queryParameters['monto'];
            final ventaId = vParam != null ? int.tryParse(vParam) : null;
            final monto = mParam != null ? double.tryParse(mParam) : null;
            return _buildFadeTransitionPage(
              state: state,
              child: QrCajeroScreen(ventaId: ventaId, monto: monto),
            );
          },
        ),

        // Rutas Proveedor
        GoRoute(
          path: '/proveedor',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const ProveedorDashboardScreen(),
          ),
        ),
        GoRoute(
          path: '/proveedor/productos',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const ProveedorProductosScreen(),
          ),
        ),
        GoRoute(
          path: '/proveedor/catalogo',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const ProveedorCatalogoScreen(),
          ),
        ),

        // Rutas de autenticación
        GoRoute(
          path: '/login',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const LoginScreen(),
          ),
        ),
        GoRoute(
          path: '/registro',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const RegistroScreen(),
          ),
        ),
      ],
    );
  }

  static CustomTransitionPage<void> _buildFadeTransitionPage({
    required GoRouterState state,
    required Widget child,
  }) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 250),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    );
  }
}
