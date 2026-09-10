"""Endpoints HTTP del módulo Catálogo. Lectura abierta, escritura admin."""
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.catalogo import schemas, service
from app.shared.db.session import get_db

router = APIRouter(prefix="/catalogo", tags=["catalogo"])

admin_only = require_roles("administrador")


# ---------- Categorías ----------
@router.get("/categorias", response_model=list[schemas.CategoriaOut])
def listar_categorias(db: Session = Depends(get_db)):
    return service.listar_categorias(db)


@router.post("/categorias", response_model=schemas.CategoriaOut, status_code=201, dependencies=[Depends(admin_only)])
def crear_categoria(data: schemas.CategoriaCreate, db: Session = Depends(get_db)):
    return service.crear_categoria(db, data)


@router.put("/categorias/{categoria_id}", response_model=schemas.CategoriaOut, dependencies=[Depends(admin_only)])
def actualizar_categoria(categoria_id: int, data: schemas.CategoriaUpdate, db: Session = Depends(get_db)):
    categoria = service.actualizar_categoria(db, categoria_id, data)
    if not categoria:
        raise HTTPException(status_code=404, detail="Categoría no encontrada")
    return categoria


@router.delete("/categorias/{categoria_id}", response_model=schemas.CategoriaOut, dependencies=[Depends(admin_only)])
def eliminar_categoria(categoria_id: int, db: Session = Depends(get_db)):
    categoria = service.eliminar_categoria(db, categoria_id)
    if not categoria:
        raise HTTPException(status_code=404, detail="Categoría no encontrada")
    return categoria


# ---------- Tallas ----------
@router.get("/tallas", response_model=list[schemas.TallaOut])
def listar_tallas(db: Session = Depends(get_db)):
    return service.listar_tallas(db)


@router.post("/tallas", response_model=schemas.TallaOut, status_code=201, dependencies=[Depends(admin_only)])
def crear_talla(data: schemas.TallaCreate, db: Session = Depends(get_db)):
    return service.crear_talla(db, data)


@router.put("/tallas/{talla_id}", response_model=schemas.TallaOut, dependencies=[Depends(admin_only)])
def actualizar_talla(talla_id: int, data: schemas.TallaUpdate, db: Session = Depends(get_db)):
    talla = service.actualizar_talla(db, talla_id, data)
    if not talla:
        raise HTTPException(status_code=404, detail="Talla no encontrada")
    return talla


@router.delete("/tallas/{talla_id}", response_model=schemas.TallaOut, dependencies=[Depends(admin_only)])
def eliminar_talla(talla_id: int, db: Session = Depends(get_db)):
    talla = service.eliminar_talla(db, talla_id)
    if not talla:
        raise HTTPException(status_code=404, detail="Talla no encontrada")
    return talla


# ---------- Colores ----------
@router.get("/colores", response_model=list[schemas.ColorOut])
def listar_colores(db: Session = Depends(get_db)):
    return service.listar_colores(db)


@router.post("/colores", response_model=schemas.ColorOut, status_code=201, dependencies=[Depends(admin_only)])
def crear_color(data: schemas.ColorCreate, db: Session = Depends(get_db)):
    return service.crear_color(db, data)


@router.put("/colores/{color_id}", response_model=schemas.ColorOut, dependencies=[Depends(admin_only)])
def actualizar_color(color_id: int, data: schemas.ColorUpdate, db: Session = Depends(get_db)):
    color = service.actualizar_color(db, color_id, data)
    if not color:
        raise HTTPException(status_code=404, detail="Color no encontrado")
    return color


@router.delete("/colores/{color_id}", response_model=schemas.ColorOut, dependencies=[Depends(admin_only)])
def eliminar_color(color_id: int, db: Session = Depends(get_db)):
    color = service.eliminar_color(db, color_id)
    if not color:
        raise HTTPException(status_code=404, detail="Color no encontrado")
    return color


# ---------- Temporadas ----------
@router.get("/temporadas", response_model=list[schemas.TemporadaOut])
def listar_temporadas(db: Session = Depends(get_db)):
    return service.listar_temporadas(db)


@router.post("/temporadas", response_model=schemas.TemporadaOut, status_code=201, dependencies=[Depends(admin_only)])
def crear_temporada(data: schemas.TemporadaCreate, db: Session = Depends(get_db)):
    return service.crear_temporada(db, data)


@router.put("/temporadas/{temporada_id}", response_model=schemas.TemporadaOut, dependencies=[Depends(admin_only)])
def actualizar_temporada(temporada_id: int, data: schemas.TemporadaUpdate, db: Session = Depends(get_db)):
    temporada = service.actualizar_temporada(db, temporada_id, data)
    if not temporada:
        raise HTTPException(status_code=404, detail="Temporada no encontrada")
    return temporada


@router.delete("/temporadas/{temporada_id}", response_model=schemas.TemporadaOut, dependencies=[Depends(admin_only)])
def eliminar_temporada(temporada_id: int, db: Session = Depends(get_db)):
    temporada = service.eliminar_temporada(db, temporada_id)
    if not temporada:
        raise HTTPException(status_code=404, detail="Temporada no encontrada")
    return temporada


# ---------- Colecciones ----------
@router.get("/colecciones", response_model=list[schemas.ColeccionOut])
def listar_colecciones(db: Session = Depends(get_db)):
    return service.listar_colecciones(db)


@router.post("/colecciones", response_model=schemas.ColeccionOut, status_code=201, dependencies=[Depends(admin_only)])
def crear_coleccion(data: schemas.ColeccionCreate, db: Session = Depends(get_db)):
    return service.crear_coleccion(db, data)


@router.put("/colecciones/{coleccion_id}", response_model=schemas.ColeccionOut, dependencies=[Depends(admin_only)])
def actualizar_coleccion(coleccion_id: int, data: schemas.ColeccionUpdate, db: Session = Depends(get_db)):
    coleccion = service.actualizar_coleccion(db, coleccion_id, data)
    if not coleccion:
        raise HTTPException(status_code=404, detail="Colección no encontrada")
    return coleccion


@router.delete("/colecciones/{coleccion_id}", response_model=schemas.ColeccionOut, dependencies=[Depends(admin_only)])
def eliminar_coleccion(coleccion_id: int, db: Session = Depends(get_db)):
    coleccion = service.eliminar_coleccion(db, coleccion_id)
    if not coleccion:
        raise HTTPException(status_code=404, detail="Colección no encontrada")
    return coleccion


# ---------- Productos ----------
@router.get("/productos", response_model=list[schemas.ProductoConDisponibilidadOut])
def listar_productos(
    categoria_id: int | None = None,
    sucursal_id: int | None = Query(None, description="Filtrar productos con stock en esta sucursal"),
    db: Session = Depends(get_db),
):
    """Lista productos con resumen de disponibilidad agregado."""
    items = service.listar_productos_con_disponibilidad(
        db, categoria_id=categoria_id, sucursal_id=sucursal_id
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
def obtener_disponibilidad(producto_id: int, db: Session = Depends(get_db)):
    """Consulta la disponibilidad de un producto en todas las sucursales."""
    result = service.obtener_disponibilidad_producto(db, producto_id)
    if not result:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    return result


@router.get("/productos/{producto_id}", response_model=schemas.ProductoOut)
def obtener_producto(producto_id: int, db: Session = Depends(get_db)):
    producto = service.obtener_producto(db, producto_id)
    if not producto:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    return producto


@router.post("/productos", response_model=schemas.ProductoOut, status_code=201, dependencies=[Depends(admin_only)])
def crear_producto(data: schemas.ProductoCreate, db: Session = Depends(get_db)):
    return service.crear_producto(db, data)


@router.put("/productos/{producto_id}", response_model=schemas.ProductoOut, dependencies=[Depends(admin_only)])
def actualizar_producto(producto_id: int, data: schemas.ProductoUpdate, db: Session = Depends(get_db)):
    producto = service.actualizar_producto(db, producto_id, data)
    if not producto:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    return producto


@router.delete("/productos/{producto_id}", response_model=schemas.ProductoOut, dependencies=[Depends(admin_only)])
def eliminar_producto(producto_id: int, db: Session = Depends(get_db)):
    producto = service.eliminar_producto(db, producto_id)
    if not producto:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    return producto
