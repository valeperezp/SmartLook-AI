import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/admin/screens/admin_dashboard_screen.dart';
import '../../features/admin/screens/admin_inventario_screen.dart';
import '../../features/admin/screens/admin_productos_screen.dart';
import '../../features/admin/screens/admin_usuarios_screen.dart';
import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/registro_screen.dart';
import '../../features/catalogo/screens/home_screen.dart';
import '../../features/encargado/screens/encargado_dashboard_screen.dart';
import '../../features/encargado/screens/encargado_inventario_screen.dart';
import '../../features/encargado/screens/encargado_reservas_screen.dart';
import '../../features/proveedor/screens/proveedor_catalogo_screen.dart';
import '../../features/proveedor/screens/proveedor_dashboard_screen.dart';
import '../../features/proveedor/screens/proveedor_productos_screen.dart';
import '../../features/reservas/screens/mis_reservas_screen.dart';

class MainShellScreen extends StatelessWidget {
  final Widget child;

  const MainShellScreen({super.key, required this.child});

  int _calculateSelectedIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    if (location.startsWith('/mis-reservas')) return 1;
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

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

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
          // Proveedor intentando entrar a login, registro, splash o rutas cliente/admin/encargado
          if (isAuthRoute ||
              location == '/' ||
              location == '/splash' ||
              location == '/mis-reservas' ||
              location.startsWith('/admin') ||
              location.startsWith('/encargado')) {
            return '/proveedor';
          }
          return null;
        } else if (rol == 'encargado_sucursal') {
          // Encargado intentando entrar a login, registro, splash o rutas cliente/admin/proveedor
          if (isAuthRoute ||
              location == '/' ||
              location == '/splash' ||
              location == '/mis-reservas' ||
              location.startsWith('/admin') ||
              location.startsWith('/proveedor')) {
            return '/encargado';
          }
          return null;
        } else if (rol == 'administrador') {
          // Admin intentando entrar a login, registro, splash o rutas cliente/encargado/proveedor
          if (isAuthRoute ||
              location == '/' ||
              location == '/splash' ||
              location == '/mis-reservas' ||
              location.startsWith('/encargado') ||
              location.startsWith('/proveedor')) {
            return '/admin';
          }
          return null;
        } else {
          // Cliente intentando entrar a login, registro, splash o rutas admin/encargado/proveedor
          if (isAuthRoute ||
              location == '/splash' ||
              location.startsWith('/admin') ||
              location.startsWith('/encargado') ||
              location.startsWith('/proveedor')) {
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
          ],
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
            child: const EncargadoPlaceholderScreen(
              title: 'Movimientos de Inventario',
              message: 'Próximamente en FASE 6.2: registro de entradas, salidas y auditoría de ajustes.',
              icon: Icons.swap_horiz,
            ),
          ),
        ),
        GoRoute(
          path: '/encargado/reservas',
          pageBuilder: (context, state) => _buildFadeTransitionPage(
            state: state,
            child: const EncargadoReservasScreen(),
          ),
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
