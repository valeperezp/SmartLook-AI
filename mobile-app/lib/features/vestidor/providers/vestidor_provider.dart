import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import '../models/producto_ar.dart';
import '../models/vestidor_prueba.dart';
import '../services/vestidor_service.dart';

class VestidorProvider extends ChangeNotifier {
  final VestidorService _service = VestidorService();
  final ImagePicker _picker = ImagePicker();

  ProductoAr? _productoActual;
  List<ProductoAr> _productos = [];
  bool _cargando = false;
  bool _procesandoFoto = false;
  String? _errorMessage;
  String? _infoMessage;

  Uint8List? _fotoUsuarioBytes;
  String? _nombreArchivoFoto;
  VestidorPrueba? _resultadoPrueba;

  ProductoAr? get productoActual => _productoActual;
  List<ProductoAr> get productos => _productos;
  bool get cargando => _cargando;
  bool get procesandoFoto => _procesandoFoto;
  String? get errorMessage => _errorMessage;
  String? get infoMessage => _infoMessage;
  Uint8List? get fotoUsuarioBytes => _fotoUsuarioBytes;
  VestidorPrueba? get resultadoPrueba => _resultadoPrueba;

  void seleccionarProducto(ProductoAr prod) {
    _productoActual = prod;
    _resultadoPrueba = null;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();
  }

  void limpiarFoto() {
    _fotoUsuarioBytes = null;
    _nombreArchivoFoto = null;
    _resultadoPrueba = null;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();
  }

  Future<void> capturarFoto(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 85,
      );

      if (picked != null) {
        final bytes = await picked.readAsBytes();
        _fotoUsuarioBytes = bytes;
        _nombreArchivoFoto = picked.name;
        _resultadoPrueba = null;
        _errorMessage = null;
        _infoMessage = null;
        notifyListeners();
      }
    } catch (e) {
      _errorMessage = 'No se pudo acceder a la cámara o galería: $e';
      notifyListeners();
    }
  }

  Future<void> generarPruebaVirtual() async {
    if (_productoActual == null) {
      _errorMessage = 'Por favor selecciona una prenda primero.';
      notifyListeners();
      return;
    }

    if (_fotoUsuarioBytes == null) {
      _errorMessage = 'Por favor sube o toma una foto tuya primero.';
      notifyListeners();
      return;
    }

    _procesandoFoto = true;
    _errorMessage = null;
    _infoMessage = null;
    notifyListeners();

    try {
      final resultado = await _service.generarPruebaVirtual(
        productoId: _productoActual!.productoId,
        fotoBytes: _fotoUsuarioBytes!,
        nombreArchivo: _nombreArchivoFoto ?? 'persona.jpg',
      );

      _resultadoPrueba = resultado;
      _infoMessage = '¡Prueba virtual generada con éxito!';
    } on DioException catch (dioErr) {
      final data = dioErr.response?.data;
      String? detail;
      if (data is Map && data.containsKey('detail')) {
        detail = data['detail']?.toString();
      }
      if (dioErr.response?.statusCode == 503) {
        _errorMessage = detail ??
            'El vestidor con IA está en preparación en el servidor. Puedes visualizar la prenda y reservarla.';
      } else {
        _errorMessage = detail ?? 'Error al procesar la imagen: ${dioErr.message}';
      }
    } catch (e) {
      _errorMessage = 'Error inesperado al generar la prueba virtual: $e';
    } finally {
      _procesandoFoto = false;
      notifyListeners();
    }
  }

  Future<void> cargarProductosCatalogo({int? seleccionarId}) async {
    _cargando = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final list = await _service.listarProductos();
      _productos = list;

      if (seleccionarId != null) {
        final match = list.where((p) => p.productoId == seleccionarId);
        if (match.isNotEmpty) {
          _productoActual = match.first;
        } else {
          await cargarProducto(seleccionarId);
        }
      } else if (_productoActual == null && list.isNotEmpty) {
        _productoActual = list.first;
      }
    } catch (e) {
      _errorMessage = 'Error al cargar productos para el vestidor: $e';
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  Future<void> cargarProducto(int id) async {
    _cargando = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final prod = await _service.obtenerProductoAR(id);
      _productoActual = prod;
      if (!_productos.any((p) => p.productoId == prod.productoId)) {
        _productos.insert(0, prod);
      }
    } catch (e) {
      _errorMessage = 'No se pudo obtener el detalle de la prenda para el vestidor';
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }
}
