import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/admin_provider.dart';

class AdminUsuariosScreen extends StatefulWidget {
  const AdminUsuariosScreen({super.key});

  @override
  State<AdminUsuariosScreen> createState() => _AdminUsuariosScreenState();
}

class _AdminUsuariosScreenState extends State<AdminUsuariosScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().cargarUsuarios();
    });
  }

  Widget _buildRoleBadge(String rol) {
    Color bgColor;
    Color textColor;
    String label;

    switch (rol.toLowerCase()) {
      case 'administrador':
        bgColor = Colors.indigo.shade100;
        textColor = Colors.indigo.shade900;
        label = 'Administrador';
        break;
      case 'encargado_sucursal':
        bgColor = Colors.orange.shade100;
        textColor = Colors.orange.shade900;
        label = 'Encargado';
        break;
      case 'proveedor':
        bgColor = Colors.green.shade100;
        textColor = Colors.green.shade900;
        label = 'Proveedor';
        break;
      case 'cliente':
      default:
        bgColor = Colors.grey.shade200;
        textColor = Colors.grey.shade800;
        label = 'Cliente';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildActivoBadge(bool activo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: activo ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: activo ? Colors.green.shade200 : Colors.grey.shade300,
        ),
      ),
      child: Text(
        activo ? 'Activo' : 'Inactivo',
        style: TextStyle(
          color: activo ? Colors.green.shade800 : Colors.grey.shade600,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final admin = context.watch<AdminProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Usuarios', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.indigo.shade800,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/admin'),
        ),
      ),
      body: admin.isLoading && admin.usuarios.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : admin.errorMessage != null && admin.usuarios.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 56, color: Colors.red),
                        const SizedBox(height: 12),
                        Text(
                          admin.errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => admin.cargarUsuarios(),
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => admin.cargarUsuarios(),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 800),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Contador arriba
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${admin.usuarios.length} usuarios registrados',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87,
                                  ),
                                ),
                                const Icon(Icons.people_outline,
                                    color: Colors.grey),
                              ],
                            ),
                          ),
                          const Divider(height: 1),

                          // Lista de usuarios
                          Expanded(
                            child: admin.usuarios.isEmpty
                                ? const Center(
                                    child: Text(
                                      'No hay usuarios',
                                      style: TextStyle(fontSize: 16),
                                    ),
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.all(12),
                                    itemCount: admin.usuarios.length,
                                    itemBuilder: (context, index) {
                                      final usuario = admin.usuarios[index];
                                      final nombre =
                                          usuario['nombre']?.toString() ??
                                              'Sin nombre';
                                      final email =
                                          usuario['email']?.toString() ?? '';
                                      final rol =
                                          usuario['rol']?.toString() ??
                                              'cliente';
                                      final activo =
                                          usuario['activo'] as bool? ?? true;

                                      return Card(
                                        elevation: 1,
                                        margin:
                                            const EdgeInsets.only(bottom: 10),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12.0),
                                          child: Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 22,
                                                backgroundColor:
                                                    Colors.indigo.shade100,
                                                child: Text(
                                                  nombre.isNotEmpty
                                                      ? nombre[0].toUpperCase()
                                                      : 'U',
                                                  style: TextStyle(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    color:
                                                        Colors.indigo.shade900,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      nombre,
                                                      style: const TextStyle(
                                                        fontSize: 15,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      email,
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        color: Colors
                                                            .grey.shade600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.end,
                                                children: [
                                                  _buildRoleBadge(rol),
                                                  const SizedBox(height: 6),
                                                  _buildActivoBadge(activo),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
    );
  }
}
