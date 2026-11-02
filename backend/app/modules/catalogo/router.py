"""Endpoints HTTP del módulo Catálogo (CU7). Lectura abierta, escritura admin.

La lectura pública muestra el catálogo de la empresa del contexto (sesión, header
X-Empresa o tienda por defecto); la escritura trabaja sobre la empresa del admin.
"""
from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session

from app.modules.auth.service import empresa_contexto, require_roles
from app.modules.catalogo import schemas, service
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db

router = APIRouter(prefix="/catalogo", tags=["catalogo"])

admin_only = require_roles("administrador")
proveedor_only = require_roles("proveedor")


def _o_404(registro, mensaje: str):
    if not registro:
        raise HTTPException(status_code=404, detail=mensaje)
    return registro


# ---------- Categorías ----------
@router.get("/categorias", response_model=list[schemas.CategoriaOut])
def listar_categorias(db: Session = Depends(get_db), empresa_id: int = Depends(empresa_contexto)):
    return service.listar_categorias(db, empresa_id)


@router.post("/categorias", response_model=schemas.CategoriaOut, status_code=201)
def crear_categoria(data: schemas.CategoriaCreate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    return service.crear_categoria(db, data, admin.empresa_id)


@router.put("/categorias/{categoria_id}", response_model=schemas.CategoriaOut)
def actualizar_categoria(
    categoria_id: int, data: schemas.CategoriaUpdate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)
):
    return _o_404(service.actualizar_categoria(db, categoria_id, data, admin.empresa_id), "Categoría no encontrada")


@router.delete("/categorias/{categoria_id}", response_model=schemas.CategoriaOut)
def eliminar_categoria(categoria_id: int, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    return _o_404(service.eliminar_categoria(db, categoria_id, admin.empresa_id), "Categoría no encontrada")


# ---------- Tallas ----------
@router.get("/tallas", response_model=list[schemas.TallaOut])
def listar_tallas(db: Session = Depends(get_db), empresa_id: int = Depends(empresa_contexto)):
    return service.listar_tallas(db, empresa_id)


@router.post("/tallas", response_model=schemas.TallaOut, status_code=201)
def crear_talla(data: schemas.TallaCreate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    return service.crear_talla(db, data, admin.empresa_id)


@router.put("/tallas/{talla_id}", response_model=schemas.TallaOut)
def actualizar_talla(
    talla_id: int, data: schemas.TallaUpdate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)
):
    return _o_404(service.actualizar_talla(db, talla_id, data, admin.empresa_id), "Talla no encontrada")


@router.delete("/tallas/{talla_id}", response_model=schemas.TallaOut)
def eliminar_talla(talla_id: int, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    return _o_404(service.eliminar_talla(db, talla_id, admin.empresa_id), "Talla no encontrada")


# ---------- Colores ----------
@router.get("/colores", response_model=list[schemas.ColorOut])
def listar_colores(db: Session = Depends(get_db), empresa_id: int = Depends(empresa_contexto)):
    return service.listar_colores(db, empresa_id)


@router.post("/colores", response_model=schemas.ColorOut, status_code=201)
def crear_color(data: schemas.ColorCreate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    return service.crear_color(db, data, admin.empresa_id)


@router.put("/colores/{color_id}", response_model=schemas.ColorOut)
def actualizar_color(
    color_id: int, data: schemas.ColorUpdate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)
):
    return _o_404(service.actualizar_color(db, color_id, data, admin.empresa_id), "Color no encontrado")


@router.delete("/colores/{color_id}", response_model=schemas.ColorOut)
def eliminar_color(color_id: int, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    return _o_404(service.eliminar_color(db, color_id, admin.empresa_id), "Color no encontrado")


# ---------- Temporadas ----------
@router.get("/temporadas", response_model=list[schemas.TemporadaOut])
def listar_temporadas(db: Session = Depends(get_db), empresa_id: int = Depends(empresa_contexto)):
    return service.listar_temporadas(db, empresa_id)


@router.post("/temporadas", response_model=schemas.TemporadaOut, status_code=201)
def crear_temporada(data: schemas.TemporadaCreate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    return service.crear_temporada(db, data, admin.empresa_id)


@router.put("/temporadas/{temporada_id}", response_model=schemas.TemporadaOut)
def actualizar_temporada(
    temporada_id: int, data: schemas.TemporadaUpdate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)
):
    return _o_404(service.actualizar_temporada(db, temporada_id, data, admin.empresa_id), "Temporada no encontrada")


@router.delete("/temporadas/{temporada_id}", response_model=schemas.TemporadaOut)
def eliminar_temporada(temporada_id: int, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    return _o_404(service.eliminar_temporada(db, temporada_id, admin.empresa_id), "Temporada no encontrada")


# ---------- Colecciones ----------
@router.get("/colecciones", response_model=list[schemas.ColeccionOut])
def listar_colecciones(db: Session = Depends(get_db), empresa_id: int = Depends(empresa_contexto)):
    return service.listar_colecciones(db, empresa_id)


@router.post("/colecciones", response_model=schemas.ColeccionOut, status_code=201)
def crear_coleccion(data: schemas.ColeccionCreate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    return service.crear_coleccion(db, data, admin.empresa_id)


@router.put("/colecciones/{coleccion_id}", response_model=schemas.ColeccionOut)
def actualizar_coleccion(
    coleccion_id: int, data: schemas.ColeccionUpdate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)
):
    return _o_404(service.actualizar_coleccion(db, coleccion_id, data, admin.empresa_id), "Colección no encontrada")


@router.delete("/colecciones/{coleccion_id}", response_model=schemas.ColeccionOut)
def eliminar_coleccion(coleccion_id: int, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    return _o_404(service.eliminar_coleccion(db, coleccion_id, admin.empresa_id), "Colección no encontrada")


# ---------- Productos ----------
@router.get("/productos", response_model=list[schemas.ProductoConDisponibilidadOut])
def listar_productos(
    categoria_id: int | None = None,
    sucursal_id: int | None = Query(None, description="Filtrar productos con stock en esta sucursal"),
    db: Session = Depends(get_db),
    empresa_id: int = Depends(empresa_contexto),
):
    """Lista productos con resumen de disponibilidad agregado."""
    items = service.listar_productos_con_disponibilidad(
        db, empresa_id, categoria_id=categoria_id, sucursal_id=sucursal_id
    )
    resultado = []
    for item in items:
        prod_dict = schemas.ProductoOut.model_validate(item["producto"]).model_dump()
        prod_dict.update({
            "total_disponible": item["total_disponible"],
            "sucursales_con_stock": item["sucursales_con_stock"],
            "estado_global": item["estado_global"],
        })
        resultado.append(prod_dict)
    return resultado


@router.get("/productos/{producto_id}/disponibilidad", response_model=schemas.ProductoDisponibilidadOut)
def obtener_disponibilidad(producto_id: int, db: Session = Depends(get_db), empresa_id: int = Depends(empresa_contexto)):
    """Consulta la disponibilidad de un producto en todas las sucursales."""
    result = service.obtener_disponibilidad_producto(db, producto_id, empresa_id)
    if not result:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    return result


@router.get("/productos/{producto_id}", response_model=schemas.ProductoOut)
def obtener_producto(producto_id: int, db: Session = Depends(get_db), empresa_id: int = Depends(empresa_contexto)):
    producto = service.obtener_producto(db, producto_id, empresa_id)
    if not producto:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    return producto


@router.post("/productos", response_model=schemas.ProductoOut, status_code=201)
def crear_producto(data: schemas.ProductoCreate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    return service.crear_producto(db, data, admin.empresa_id)


@router.put("/productos/{producto_id}", response_model=schemas.ProductoOut)
def actualizar_producto(
    producto_id: int, data: schemas.ProductoUpdate, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)
):
    producto = service.actualizar_producto(db, producto_id, data, admin.empresa_id)
    if not producto:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    return producto


@router.delete("/productos/{producto_id}", response_model=schemas.ProductoOut)
def eliminar_producto(producto_id: int, db: Session = Depends(get_db), admin: Usuario = Depends(admin_only)):
    producto = service.eliminar_producto(db, producto_id, admin.empresa_id)
    if not producto:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    return producto


@router.post("/productos/{producto_id}/imagen", response_model=schemas.ProductoOut)
async def subir_imagen_producto(
    producto_id: int,
    archivo: UploadFile = File(...),
    db: Session = Depends(get_db),
    admin: Usuario = Depends(admin_only),
):
    """Sube una imagen a Supabase Storage y la asocia al producto."""
    contenido = await archivo.read()
    return await run_in_threadpool(
        service.subir_imagen_producto,
        db, producto_id, contenido, archivo.filename or "imagen.jpg", archivo.content_type or "image/jpeg",
        admin.empresa_id,
    )


# ---------- Productos del Proveedor (CU18) ----------
@router.get("/mis-productos", response_model=list[schemas.ProductoOut])
def listar_mis_productos(
    incluir_inactivos: bool = Query(False, description="Incluir productos inactivos"),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(proveedor_only),
):
    if not usuario.proveedor_id:
        raise HTTPException(status_code=403, detail="El proveedor no tiene proveedor_id asignado")
    return service.listar_productos_por_proveedor(db, usuario.proveedor_id, incluir_inactivos=incluir_inactivos)


@router.post("/mis-productos", response_model=schemas.ProductoOut, status_code=201)
def crear_mi_producto(
    data: schemas.ProductoCreate,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(proveedor_only),
):
    if not usuario.proveedor_id:
        raise HTTPException(status_code=403, detail="El proveedor no tiene proveedor_id asignado")
    return service.crear_producto_proveedor(db, data, usuario.proveedor_id, usuario.empresa_id)


@router.put("/mis-productos/{producto_id}", response_model=schemas.ProductoOut)
def actualizar_mi_producto(
    producto_id: int,
    data: schemas.ProductoUpdate,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(proveedor_only),
):
    if not usuario.proveedor_id:
        raise HTTPException(status_code=403, detail="El proveedor no tiene proveedor_id asignado")
    producto = service.actualizar_producto_proveedor(db, producto_id, data, usuario.proveedor_id)
    if not producto:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    return producto


@router.delete("/mis-productos/{producto_id}", response_model=schemas.ProductoOut)
def eliminar_mi_producto(
    producto_id: int,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(proveedor_only),
):
    if not usuario.proveedor_id:
        raise HTTPException(status_code=403, detail="El proveedor no tiene proveedor_id asignado")
    producto = service.eliminar_producto_proveedor(db, producto_id, usuario.proveedor_id)
    if not producto:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    return producto
