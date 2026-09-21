import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/empty_state.dart';
import '../../../../core/widgets/loading_state.dart';
import '../providers/ia_config_provider.dart';

class IaPreset {
  final String nombre;
  final String baseUrl;
  final String modelo;
  final String ayuda;

  const IaPreset({
    required this.nombre,
    required this.baseUrl,
    required this.modelo,
    required this.ayuda,
  });
}

const List<IaPreset> kIaPresets = [
  IaPreset(
    nombre: 'Ollama (local)',
    baseUrl: 'http://host.docker.internal:11434/v1',
    modelo: 'llama3.2:1b',
    ayuda:
        'Requiere tener Ollama corriendo en tu máquina con el modelo descargado. No necesita API key.',
  ),
  IaPreset(
    nombre: 'OpenAI (nube)',
    baseUrl: 'https://api.openai.com/v1',
    modelo: 'gpt-4o-mini',
    ayuda: 'Requiere una API key de OpenAI con crédito disponible.',
  ),
  IaPreset(
    nombre: 'Groq (nube, gratis, rápido)',
    baseUrl: 'https://api.groq.com/openai/v1',
    modelo: 'llama-3.1-8b-instant',
    ayuda:
        'Requiere una API key gratuita de console.groq.com. Responde en menos de 1 segundo.',
  ),
];

class IaConfigScreen extends StatefulWidget {
  const IaConfigScreen({super.key});

  @override
  State<IaConfigScreen> createState() => _IaConfigScreenState();
}

class _IaConfigScreenState extends State<IaConfigScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _baseUrlCtrl;
  late TextEditingController _modeloCtrl;
  late TextEditingController _apiKeyCtrl;

  bool _obscureApiKey = true;
  bool _inicializado = false;

  @override
  void initState() {
    super.initState();
    _baseUrlCtrl = TextEditingController();
    _modeloCtrl = TextEditingController();
    _apiKeyCtrl = TextEditingController();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<IaConfigProvider>().cargarConfig();
    });
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _modeloCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
  }

  void _aplicarPreset(IaPreset preset) {
    setState(() {
      _baseUrlCtrl.text = preset.baseUrl;
      _modeloCtrl.text = preset.modelo;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Preset "${preset.nombre}" aplicado'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final messenger = ScaffoldMessenger.of(context);
    final prov = context.read<IaConfigProvider>();

    final exito = await prov.actualizarConfig(
      baseUrl: _baseUrlCtrl.text,
      modelo: _modeloCtrl.text,
      apiKey: _apiKeyCtrl.text.isNotEmpty ? _apiKeyCtrl.text : null,
    );

    if (exito) {
      _apiKeyCtrl.clear();
      messenger.showSnackBar(
        SnackBar(
          content: const Text('Configuración guardada exitosamente'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(prov.errorMessage ?? 'Error al guardar configuración'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<IaConfigProvider>();
    final config = prov.config;

    // Sincronizar controladores con la config cargada una vez
    if (config != null && !_inicializado) {
      _baseUrlCtrl.text = config.baseUrl;
      _modeloCtrl.text = config.modelo;
      _inicializado = true;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Configuración de IA',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.indigo.shade800,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/admin'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Recargar',
            onPressed: prov.isLoading ? null : () => prov.cargarConfig(),
          ),
        ],
      ),
      body: prov.isLoading && config == null
          ? const LoadingState(mensaje: 'Cargando configuración de IA...')
          : prov.errorMessage != null && config == null
              ? EmptyState(
                  icono: Icons.error_outline,
                  titulo: 'Error al cargar',
                  mensaje: prov.errorMessage,
                  onReintentar: () => prov.cargarConfig(),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Banner descriptivo
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.indigo.shade50,
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusMd),
                                border: Border.all(
                                  color: Colors.indigo.shade200,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.auto_awesome,
                                    color: Colors.indigo.shade800,
                                    size: 28,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Ajusta el proveedor y modelo de Inteligencia Artificial que procesa las recomendaciones del vestidor y el asistente de compras.',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.indigo.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Presets rápidos
                            const Text(
                              'Presets recomendados',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: kIaPresets.map((preset) {
                                return ActionChip(
                                  avatar: const Icon(Icons.flash_on, size: 16),
                                  label: Text(preset.nombre),
                                  backgroundColor: AppTheme.surface,
                                  side: const BorderSide(
                                    color: AppTheme.border,
                                  ),
                                  onPressed: () => _aplicarPreset(preset),
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 20),

                            // Card Formulario
                            Card(
                              color: AppTheme.surface,
                              shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(AppTheme.radiusMd),
                                side: const BorderSide(
                                  color: AppTheme.border,
                                  width: 1,
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Parámetros del proveedor',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // Base URL
                                    TextFormField(
                                      controller: _baseUrlCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Base URL de la API *',
                                        hintText: 'https://api.openai.com/v1',
                                        prefixIcon: Icon(Icons.link),
                                        border: OutlineInputBorder(),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) {
                                          return 'La Base URL es obligatoria';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 16),

                                    // Modelo
                                    TextFormField(
                                      controller: _modeloCtrl,
                                      decoration: const InputDecoration(
                                        labelText: 'Nombre del Modelo *',
                                        hintText: 'gpt-4o-mini, llama3.2:1b, etc.',
                                        prefixIcon: Icon(Icons.memory),
                                        border: OutlineInputBorder(),
                                      ),
                                      validator: (v) {
                                        if (v == null || v.trim().isEmpty) {
                                          return 'El nombre del modelo es obligatorio';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 16),

                                    // API Key
                                    TextFormField(
                                      controller: _apiKeyCtrl,
                                      obscureText: _obscureApiKey,
                                      decoration: InputDecoration(
                                        labelText: 'API Key',
                                        hintText: config?.apiKeyConfigurada == true
                                            ? '•••••••• (conservar actual o escribir nueva)'
                                            : 'sk-...',
                                        prefixIcon: const Icon(Icons.key),
                                        border: const OutlineInputBorder(),
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _obscureApiKey
                                                ? Icons.visibility
                                                : Icons.visibility_off,
                                          ),
                                          onPressed: () => setState(() =>
                                              _obscureApiKey = !_obscureApiKey),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(
                                          config?.apiKeyConfigurada == true
                                              ? Icons.check_circle
                                              : Icons.info_outline,
                                          size: 15,
                                          color: config?.apiKeyConfigurada == true
                                              ? Colors.teal.shade700
                                              : Colors.grey.shade600,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          config?.apiKeyConfigurada == true
                                              ? 'API Key actualmente configurada en el servidor'
                                              : 'Sin API Key guardada (no requerida para Ollama local)',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: config?.apiKeyConfigurada == true
                                                ? Colors.teal.shade700
                                                : Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),

                            // Resultado de prueba de conexión (si existe)
                            if (prov.resultadoPrueba != null) ...[
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: prov.resultadoPrueba!.ok
                                      ? Colors.green.shade50
                                      : Colors.red.shade50,
                                  borderRadius:
                                      BorderRadius.circular(AppTheme.radiusMd),
                                  border: Border.all(
                                    color: prov.resultadoPrueba!.ok
                                        ? Colors.green.shade300
                                        : Colors.red.shade300,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          prov.resultadoPrueba!.ok
                                              ? Icons.check_circle
                                              : Icons.cancel,
                                          color: prov.resultadoPrueba!.ok
                                              ? Colors.green.shade700
                                              : Colors.red.shade700,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          prov.resultadoPrueba!.ok
                                              ? 'Conexión Exitosa'
                                              : 'Error de Conexión',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: prov.resultadoPrueba!.ok
                                              ? Colors.green.shade900
                                              : Colors.red.shade900,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      prov.resultadoPrueba!.ok
                                          ? (prov.resultadoPrueba!.respuesta ??
                                              'El modelo respondió correctamente.')
                                          : (prov.resultadoPrueba!.error ??
                                              'No se pudo conectar con el servidor de IA.'),
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: prov.resultadoPrueba!.ok
                                            ? Colors.green.shade800
                                            : Colors.red.shade800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                            ],

                            // Botones Acción: Probar Conexión & Guardar Cambios
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                    ),
                                    icon: prov.isTesting
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.network_check),
                                    label: Text(
                                      prov.isTesting
                                          ? 'Probando...'
                                          : 'Probar conexión',
                                    ),
                                    onPressed: prov.isTesting || prov.isSaving
                                        ? null
                                        : () => prov.probarConexion(),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                      ),
                                      backgroundColor: Colors.indigo.shade700,
                                      foregroundColor: Colors.white,
                                    ),
                                    icon: prov.isSaving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.save),
                                    label: Text(
                                      prov.isSaving
                                          ? 'Guardando...'
                                          : 'Guardar cambios',
                                    ),
                                    onPressed: prov.isSaving || prov.isTesting
                                        ? null
                                        : _guardar,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }
}
