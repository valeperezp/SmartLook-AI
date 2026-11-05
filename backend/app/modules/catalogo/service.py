"""Lógica de negocio del módulo Catálogo (independiente de FastAPI/HTTP).

CU7 — cada empresa tiene su propio catálogo maestro y sus productos. Todas las
funciones reciben `empresa_id`; un registro de otra empresa se trata como inexistente.
"""
import uuid

import httpx
from fastapi import HTTPException
from sqlalchemy import func
from sqlalchemy.orm import Session

from app.modules.catalogo import models, schemas
from app.modules.empresas import service as empresas_service
from app.modules.proveedores.models import Proveedor
from app.shared.core.config import settings
from app.shared.db.tenant import asegurar_de_empresa
from app.shared.utils.imagenes import validar_imagen


def _aplicar_update(instancia, data) -> None:
    for campo, valor in data.model_dump(exclude_unset=True).items():
        setattr(instancia, campo, valor)


# ---------- Catálogo maestro: helpers comunes ----------
def _listar(db: Session, modelo, empresa_id: int, orden):
    return db.query(modelo).filter(modelo.empresa_id == empresa_id).order_by(orden).all()


def _obtener(db: Session, modelo, registro_id: int, empresa_id: int):
    return db.query(modelo).filter(modelo.id == registro_id, modelo.empresa_id == empresa_id).first()


def _validar_nombre_unico(db: Session, modelo, nombre: str | None, empresa_id: int, excluir_id: int | None = None) -> None:
    if nombre is None:
        return
    query = db.query(modelo.id).filter(
        modelo.empresa_id == empresa_id, func.lower(modelo.nombre) == nombre.strip().lower()
    )
    if excluir_id is not None:
        query = query.filter(modelo.id != excluir_id)
    if query.first():
        raise HTTPException(status_code=400, detail=f"Ya existe '{nombre}' en tu catálogo")


def _crear(db: Session, modelo, data, empresa_id: int):
    _validar_nombre_unico(db, modelo, data.nombre, empresa_id)
    instancia = modelo(**data.model_dump(), empresa_id=empresa_id)
    db.add(instancia)
    db.commit()
    db.refresh(instancia)
    return instancia


def _actualizar(db: Session, modelo, registro_id: int, data, empresa_id: int):
    instancia = _obtener(db, modelo, registro_id, empresa_id)
    if not instancia:
        return None
    _validar_nombre_unico(db, modelo, data.model_dump(exclude_unset=True).get("nombre"), empresa_id, instancia.id)
    _aplicar_update(instancia, data)
    db.commit()
    db.refresh(instancia)
    return instancia


def _desactivar(db: Session, modelo, registro_id: int, empresa_id: int):
    instancia = _obtener(db, modelo, registro_id, empresa_id)
    if not instancia:
        return None
    instancia.activo = False
    db.commit()
    db.refresh(instancia)
    return instancia


# ---------- Categoría ----------
def listar_categorias(db: Session, empresa_id: int) -> list[models.Categoria]:
    return _listar(db, models.Categoria, empresa_id, models.Categoria.nombre)


def obtener_categoria(db: Session, categoria_id: int, empresa_id: int) -> models.Categoria | None:
    return _obtener(db, models.Categoria, categoria_id, empresa_id)


def crear_categoria(db: Session, data: schemas.CategoriaCreate, empresa_id: int) -> models.Categoria:
    return _crear(db, models.Categoria, data, empresa_id)


def actualizar_categoria(
    db: Session, categoria_id: int, data: schemas.CategoriaUpdate, empresa_id: int
) -> models.Categoria | None:
    return _actualizar(db, models.Categoria, categoria_id, data, empresa_id)


def eliminar_categoria(db: Session, categoria_id: int, empresa_id: int) -> models.Categoria | None:
    return _desactivar(db, models.Categoria, categoria_id, empresa_id)


# ---------- Talla ----------
def listar_tallas(db: Session, empresa_id: int) -> list[models.Talla]:
    return _listar(db, models.Talla, empresa_id, models.Talla.id)


def obtener_talla(db: Session, talla_id: int, empresa_id: int) -> models.Talla | None:
    return _obtener(db, models.Talla, talla_id, empresa_id)


def crear_talla(db: Session, data: schemas.TallaCreate, empresa_id: int) -> models.Talla:
    return _crear(db, models.Talla, data, empresa_id)


def actualizar_talla(db: Session, talla_id: int, data: schemas.TallaUpdate, empresa_id: int) -> models.Talla | None:
    return _actualizar(db, models.Talla, talla_id, data, empresa_id)


def eliminar_talla(db: Session, talla_id: int, empresa_id: int) -> models.Talla | None:
    return _desactivar(db, models.Talla, talla_id, empresa_id)


# ---------- Color ----------
def listar_colores(db: Session, empresa_id: int) -> list[models.Color]:
    return _listar(db, models.Color, empresa_id, models.Color.id)


def obtener_color(db: Session, color_id: int, empresa_id: int) -> models.Color | None:
    return _obtener(db, models.Color, color_id, empresa_id)


def crear_color(db: Session, data: schemas.ColorCreate, empresa_id: int) -> models.Color:
    return _crear(db, models.Color, data, empresa_id)


def actualizar_color(db: Session, color_id: int, data: schemas.ColorUpdate, empresa_id: int) -> models.Color | None:
    return _actualizar(db, models.Color, color_id, data, empresa_id)


def eliminar_color(db: Session, color_id: int, empresa_id: int) -> models.Color | None:
    return _desactivar(db, models.Color, color_id, empresa_id)


# ---------- Temporada ----------
def listar_temporadas(db: Session, empresa_id: int) -> list[models.Temporada]:
    return _listar(db, models.Temporada, empresa_id, models.Temporada.id)


def obtener_temporada(db: Session, temporada_id: int, empresa_id: int) -> models.Temporada | None:
    return _obtener(db, models.Temporada, temporada_id, empresa_id)


def crear_temporada(db: Session, data: schemas.TemporadaCreate, empresa_id: int) -> models.Temporada:
    return _crear(db, models.Temporada, data, empresa_id)


def actualizar_temporada(
    db: Session, temporada_id: int, data: schemas.TemporadaUpdate, empresa_id: int
) -> models.Temporada | None:
    return _actualizar(db, models.Temporada, temporada_id, data, empresa_id)


def eliminar_temporada(db: Session, temporada_id: int, empresa_id: int) -> models.Temporada | None:
    return _desactivar(db, models.Temporada, temporada_id, empresa_id)


# ---------- Colección ----------
def listar_colecciones(db: Session, empresa_id: int) -> list[models.Coleccion]:
    return _listar(db, models.Coleccion, empresa_id, models.Coleccion.id)


def obtener_coleccion(db: Session, coleccion_id: int, empresa_id: int) -> models.Coleccion | None:
    return _obtener(db, models.Coleccion, coleccion_id, empresa_id)


def crear_coleccion(db: Session, data: schemas.ColeccionCreate, empresa_id: int) -> models.Coleccion:
    asegurar_de_empresa(db, models.Temporada, data.temporada_id, empresa_id, "Temporada")
    coleccion = models.Coleccion(**data.model_dump(), empresa_id=empresa_id)
    db.add(coleccion)
    db.commit()
    db.refresh(coleccion)
    return coleccion


def actualizar_coleccion(
    db: Session, coleccion_id: int, data: schemas.ColeccionUpdate, empresa_id: int
) -> models.Coleccion | None:
    coleccion = obtener_coleccion(db, coleccion_id, empresa_id)
    if not coleccion:
        return None
    asegurar_de_empresa(db, models.Temporada, data.temporada_id, empresa_id, "Temporada")
    _aplicar_update(coleccion, data)
    db.commit()
    db.refresh(coleccion)
    return coleccion


def eliminar_coleccion(db: Session, coleccion_id: int, empresa_id: int) -> models.Coleccion | None:
    return _desactivar(db, models.Coleccion, coleccion_id, empresa_id)


# ---------- Producto ----------
def listar_productos(
    db: Session, empresa_id: int, categoria_id: int | None = None, incluir_inactivos: bool = False
) -> list[models.Producto]:
    query = db.query(models.Producto).filter(models.Producto.empresa_id == empresa_id)
    if not incluir_inactivos:
        query = query.filter(models.Producto.activo.is_(True))
    if categoria_id:
        query = query.filter(models.Producto.categoria_id == categoria_id)
    return query.order_by(models.Producto.id).all()


def obtener_producto(db: Session, producto_id: int, empresa_id: int) -> models.Producto | None:
    return _obtener(db, models.Producto, producto_id, empresa_id)


def _validar_referencias_producto(db: Session, data, empresa_id: int) -> None:
    """Categoría, temporada, colección y proveedor tienen que ser de la misma empresa."""
    campos = data.model_dump(exclude_unset=True)
    asegurar_de_empresa(db, models.Categoria, campos.get("categoria_id"), empresa_id, "Categoría")
    asegurar_de_empresa(db, models.Temporada, campos.get("temporada_id"), empresa_id, "Temporada")
    asegurar_de_empresa(db, models.Coleccion, campos.get("coleccion_id"), empresa_id, "Colección")
    asegurar_de_empresa(db, Proveedor, campos.get("proveedor_id"), empresa_id, "Proveedor")


def _verificar_limite_si_reactiva(db: Session, producto: models.Producto, data: schemas.ProductoUpdate) -> None:
    """Reactivar un producto vuelve a ocupar un lugar del plan (CU4)."""
    if data.activo is True and not producto.activo:
        empresas_service.verificar_limite(db, producto.empresa_id, "productos")


def _validar_precio(precio: float | None) -> None:
    """CU7 6a."""
    if precio is not None and precio < 0:
        raise HTTPException(status_code=400, detail="El precio no puede ser negativo")


def _validar_datos_producto(nombre: str | None, precio: float | None) -> None:
    if nombre is not None and not nombre.strip():
        raise HTTPException(status_code=400, detail="Ingrese el nombre del producto")
    _validar_precio(precio)


def _texto_variante(db: Session, talla_id: int | None, color_id: int | None) -> str:
    talla = db.get(models.Talla, talla_id) if talla_id else None
    color = db.get(models.Color, color_id) if color_id else None
    return f"talla {talla.nombre if talla else '-'} y color {color.nombre if color else '-'}"


def _buscar_variante(db: Session, producto_id: int, talla_id: int | None, color_id: int | None):
    return (
        db.query(models.VarianteProducto)
        .filter(
            models.VarianteProducto.producto_id == producto_id,
            models.VarianteProducto.talla_id.is_not_distinct_from(talla_id),
            models.VarianteProducto.color_id.is_not_distinct_from(color_id),
        )
        .first()
    )


def _nueva_variante(db: Session, producto: models.Producto, data: schemas.VarianteCreate, empresa_id: int):
    asegurar_de_empresa(db, models.Talla, data.talla_id, empresa_id, "Talla")
    asegurar_de_empresa(db, models.Color, data.color_id, empresa_id, "Color")
    _validar_precio(data.precio)
    existente = _buscar_variante(db, producto.id, data.talla_id, data.color_id) if producto.id else None
    if existente is not None and existente.activo:  # 6b
        raise HTTPException(
            status_code=400,
            detail=f"El producto ya tiene la variante {_texto_variante(db, data.talla_id, data.color_id)}",
        )
    if existente is not None:  # estaba desactivada: se reactiva
        existente.activo, existente.precio, existente.sku = True, data.precio, data.sku
        return existente
    variante = models.VarianteProducto(
        talla_id=data.talla_id, color_id=data.color_id, precio=data.precio, sku=data.sku, activo=True,
    )
    producto.variantes.append(variante)
    return variante


def crear_producto(db: Session, data: schemas.ProductoCreate, empresa_id: int) -> models.Producto:
    _validar_datos_producto(data.nombre, data.precio)
    _validar_referencias_producto(db, data, empresa_id)
    empresas_service.verificar_limite(db, empresa_id, "productos")
    combinaciones = [(v.talla_id, v.color_id) for v in data.variantes]
    if len(combinaciones) != len(set(combinaciones)):
        raise HTTPException(status_code=400, detail="Hay variantes repetidas: cada talla y color va una sola vez")
    producto = models.Producto(**data.model_dump(exclude={"variantes"}), empresa_id=empresa_id)
    db.add(producto)
    for variante in data.variantes:
        _nueva_variante(db, producto, variante, empresa_id)
    db.commit()
    db.refresh(producto)
    return producto


def agregar_variante(
    db: Session, producto_id: int, data: schemas.VarianteCreate, empresa_id: int
) -> models.VarianteProducto | None:
    producto = obtener_producto(db, producto_id, empresa_id)
    if not producto:
        return None
    variante = _nueva_variante(db, producto, data, empresa_id)
    db.commit()
    db.refresh(variante)
    return variante


def desactivar_variante(db: Session, producto_id: int, variante_id: int, empresa_id: int):
    producto = obtener_producto(db, producto_id, empresa_id)
    variante = next((v for v in producto.variantes if v.id == variante_id), None) if producto else None
    if variante is None:
        return None
    variante.activo = False
    db.commit()
    db.refresh(variante)
    return variante


def variantes_desde_inventario(db: Session) -> int:
    """Registra como variante cada combinación producto + talla + color que ya tiene inventario.

    Sirve para bases creadas antes de que existieran las variantes. Devuelve cuántas creó.
    """
    from app.modules.inventario.models import Inventario  # import local: inventario depende de catálogo

    combinaciones = {
        (i.producto_id, i.talla_id, i.color_id)
        for i in db.query(Inventario.producto_id, Inventario.talla_id, Inventario.color_id).distinct()
    }
    existentes = {
        (v.producto_id, v.talla_id, v.color_id)
        for v in db.query(models.VarianteProducto.producto_id, models.VarianteProducto.talla_id,
                          models.VarianteProducto.color_id)
    }
    nuevas = sorted(combinaciones - existentes, key=lambda c: (c[0], c[1] or 0, c[2] or 0))
    for producto_id, talla_id, color_id in nuevas:
        db.add(models.VarianteProducto(producto_id=producto_id, talla_id=talla_id, color_id=color_id, activo=True))
    return len(nuevas)


def registrar_variante_si_falta(db: Session, producto_id: int, talla_id: int | None, color_id: int | None) -> None:
    """Al cargar inventario de una combinación nueva, la variante queda registrada en el catálogo."""
    existente = _buscar_variante(db, producto_id, talla_id, color_id)
    if existente is None:
        db.add(models.VarianteProducto(producto_id=producto_id, talla_id=talla_id, color_id=color_id, activo=True))
    elif not existente.activo:
        existente.activo = True


def actualizar_producto(
    db: Session, producto_id: int, data: schemas.ProductoUpdate, empresa_id: int
) -> models.Producto | None:
    producto = obtener_producto(db, producto_id, empresa_id)
    if not producto:
        return None
    _validar_datos_producto(data.nombre, data.precio)
    _validar_referencias_producto(db, data, empresa_id)
    _verificar_limite_si_reactiva(db, producto, data)
    _aplicar_update(producto, data)
    db.commit()
    db.refresh(producto)
    return producto


def eliminar_producto(db: Session, producto_id: int, empresa_id: int) -> models.Producto | None:
    return _desactivar(db, models.Producto, producto_id, empresa_id)


def subir_imagen_producto(
    db: Session, producto_id: int, contenido: bytes, nombre_archivo: str, content_type: str, empresa_id: int
) -> models.Producto:
    """
    Sube el archivo a Supabase Storage (bucket público) usando la service_role key,
    y guarda la URL pública resultante en el producto. Lanza HTTPException si algo falla.
    """
    if not settings.supabase_url or not settings.supabase_service_role_key:
        raise HTTPException(
            status_code=500,
            detail="Supabase Storage no está configurado (faltan SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY).",
        )

    producto = obtener_producto(db, producto_id, empresa_id)
    if not producto:
        raise HTTPException(status_code=404, detail="Producto no encontrado")

    # Tamano y magic bytes; el tipo y la extension salen del contenido real, no del nombre/cabecera del cliente
    content_type, extension = validar_imagen(contenido)
    ruta_archivo = f"producto-{producto_id}-{uuid.uuid4().hex}.{extension}"
    bucket = settings.supabase_storage_bucket

    respuesta = httpx.post(
        f"{settings.supabase_url}/storage/v1/object/{bucket}/{ruta_archivo}",
        content=contenido,
        headers={
            "Authorization": f"Bearer {settings.supabase_service_role_key}",
            "apikey": settings.supabase_service_role_key,
            "Content-Type": content_type or "application/octet-stream",
        },
        timeout=30.0,
    )
    if respuesta.status_code >= 400:
        raise HTTPException(
            status_code=502,
            detail=f"No se pudo subir la imagen a Supabase Storage: {respuesta.text}",
        )

    url_publica = f"{settings.supabase_url}/storage/v1/object/public/{bucket}/{ruta_archivo}"
    producto.imagen_url = url_publica
    db.commit()
    db.refresh(producto)
    return producto


def _calcular_estado_disponibilidad(total: int, stock_minimo: int = 5) -> str:
    """Calcula el estado agregado según cantidad total."""
    if total == 0:
        return "agotado"
    if total <= stock_minimo:
        return "bajo"
    return "disponible"


def obtener_disponibilidad_producto(db: Session, producto_id: int, empresa_id: int) -> dict | None:
    """
    Devuelve la disponibilidad de un producto agrupada por sucursal,
    con desglose por talla y color.
    """
    from app.modules.inventario.models import Inventario
    from app.modules.sucursales.models import Sucursal

    producto = obtener_producto(db, producto_id, empresa_id)
    if not producto:
        return None

    # Obtener todas las sucursales activas de la empresa
    sucursales = (
        db.query(Sucursal)
        .filter(Sucursal.activa.is_(True), Sucursal.empresa_id == empresa_id)
        .order_by(Sucursal.id)
        .all()
    )

    disponibilidad = []
    total_global = 0
    sucursales_con_stock = 0

    for suc in sucursales:
        # Obtener items de inventario de este producto en esta sucursal
        items = (
            db.query(Inventario)
            .filter(
                Inventario.producto_id == producto_id,
                Inventario.sucursal_id == suc.id,
                Inventario.activo.is_(True),
            )
            .all()
        )

        total_sucursal = sum(item.cantidad_disponible for item in items)
        total_global += total_sucursal
        if total_sucursal > 0:
            sucursales_con_stock += 1

        disponibilidad.append({
            "sucursal_id": suc.id,
            "nombre_sucursal": suc.nombre,
            "ciudad": getattr(suc, "ciudad", None),
            "total_disponible": total_sucursal,
            "estado": _calcular_estado_disponibilidad(total_sucursal),
            "items": [
                {
                    "talla_id": item.talla_id,
                    "nombre_talla": item.nombre_talla,
                    "color_id": item.color_id,
                    "nombre_color": item.nombre_color,
                    "cantidad_disponible": item.cantidad_disponible,
                    "cantidad_reservada": item.cantidad_reservada,
                    "cantidad_vendida": item.cantidad_vendida,
                }
                for item in items
            ],
            "total_reservada": sum(item.cantidad_reservada for item in items),
            "total_vendida": sum(item.cantidad_vendida for item in items),
        })

    return {
        "producto_id": producto.id,
        "nombre_producto": producto.nombre,
        "precio": float(producto.precio),
        "imagen_url": producto.imagen_url,
        "total_global": total_global,
        "sucursales_con_stock": sucursales_con_stock,
        "disponibilidad": disponibilidad,
    }


def listar_productos_con_disponibilidad(
    db: Session,
    empresa_id: int,
    categoria_id: int | None = None,
    sucursal_id: int | None = None,
) -> list[dict]:
    """
    Lista productos con su resumen de disponibilidad agregado.
    Si sucursal_id se especifica, solo devuelve productos con stock en esa sucursal.
    """
    from app.modules.inventario.models import Inventario

    productos = listar_productos(db, empresa_id, categoria_id=categoria_id)
    resultados = []

    for prod in productos:
        query = (
            db.query(Inventario)
            .filter(
                Inventario.producto_id == prod.id,
                Inventario.activo.is_(True),
            )
        )
        if sucursal_id is not None:
            query = query.filter(Inventario.sucursal_id == sucursal_id)

        items = query.all()
        total_disponible = sum(item.cantidad_disponible for item in items)
        sucursales_ids = set(item.sucursal_id for item in items if item.cantidad_disponible > 0)

        resultados.append({
            "producto": prod,
            "total_disponible": total_disponible,
            "sucursales_con_stock": len(sucursales_ids),
            "estado_global": _calcular_estado_disponibilidad(total_disponible),
        })

    return resultados


# =========================================================================
# GESTIÓN DE PRODUCTOS POR PROVEEDOR (CU18)
# =========================================================================

def listar_productos_por_proveedor(db: Session, proveedor_id: int, incluir_inactivos: bool = False) -> list[models.Producto]:
    """Lista los productos asociados a un proveedor específico."""
    query = db.query(models.Producto).filter(models.Producto.proveedor_id == proveedor_id)
    if not incluir_inactivos:
        query = query.filter(models.Producto.activo.is_(True))
    return query.order_by(models.Producto.nombre).all()


def crear_producto_proveedor(
    db: Session, data: schemas.ProductoCreate, proveedor_id: int, empresa_id: int
) -> models.Producto:
    """Crea un producto asignándolo automáticamente al proveedor."""
    _validar_datos_producto(data.nombre, data.precio)
    _validar_referencias_producto(db, data.model_copy(update={"proveedor_id": None}), empresa_id)
    empresas_service.verificar_limite(db, empresa_id, "productos")
    producto = models.Producto(
        empresa_id=empresa_id,
        nombre=data.nombre,
        descripcion=data.descripcion,
        precio=data.precio,
        categoria_id=data.categoria_id,
        temporada_id=data.temporada_id,
        coleccion_id=data.coleccion_id,
        proveedor_id=proveedor_id,
        modelo_ar_url=data.modelo_ar_url,
    )
    db.add(producto)
    db.commit()
    db.refresh(producto)
    return producto


def actualizar_producto_proveedor(db: Session, producto_id: int, data: schemas.ProductoUpdate, proveedor_id: int) -> models.Producto | None:
    """Actualiza un producto validando que sea del proveedor. NO permite cambiar proveedor_id."""
    producto = db.query(models.Producto).filter(models.Producto.id == producto_id).first()
    if not producto:
        return None
    if producto.proveedor_id != proveedor_id:
        raise HTTPException(status_code=403, detail="No puede modificar productos de otro proveedor")
    _validar_referencias_producto(db, data.model_copy(update={"proveedor_id": None}), producto.empresa_id)
    _verificar_limite_si_reactiva(db, producto, data)

    # Aplicar solo los campos permitidos (excluir proveedor_id)
    datos = data.model_dump(exclude_unset=True, exclude={'proveedor_id'})
    for campo, valor in datos.items():
        setattr(producto, campo, valor)

    db.commit()
    db.refresh(producto)
    return producto


def eliminar_producto_proveedor(db: Session, producto_id: int, proveedor_id: int) -> models.Producto | None:
    """Desactiva un producto validando que sea del proveedor."""
    producto = db.query(models.Producto).filter(models.Producto.id == producto_id).first()
    if not producto:
        return None
    if producto.proveedor_id != proveedor_id:
        raise HTTPException(status_code=403, detail="No puede desactivar productos de otro proveedor")
    producto.activo = False
    db.commit()
    db.refresh(producto)
    return producto

