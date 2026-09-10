"""Endpoints HTTP del módulo Inventario (CU11 consulta global y CU15 gestión de sucursal)."""
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.inventario import models, schemas, service
from app.modules.sucursales.models import Sucursal
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db

router = APIRouter(prefix="/inventario", tags=["inventario"])

admin_only = require_roles("administrador")
admin_or_encargado = require_roles("administrador", "encargado_sucursal")


def _validar_sucursal_usuario(usuario: Usuario, sucursal_id: int | None) -> int | None:
    """
    Valida y resuelve la sucursal permitida para el usuario.
    Si es encargado_sucursal, restringe forzosamente a su sucursal_id.
    Si es administrador, permite sucursal_id opcional (None = todas).
    """
    if usuario.rol == "encargado_sucursal":
        if not usuario.sucursal_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="El encargado de sucursal no tiene una sucursal asignada.",
            )
        if sucursal_id is not None and sucursal_id != usuario.sucursal_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="No tiene permisos para acceder o gestionar otra sucursal.",
            )
        return usuario.sucursal_id
    return sucursal_id


def _obtener_y_validar_inventario(db: Session, inventario_id: int, usuario: Usuario) -> models.Inventario:
    """Obtiene el registro de inventario y valida que pertenezca a la sucursal del encargado."""
    inv = service.obtener_inventario(db, inventario_id)
    if not inv:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Registro de inventario no encontrado.",
        )
    if usuario.rol == "encargado_sucursal":
        if not usuario.sucursal_id or inv.sucursal_id != usuario.sucursal_id:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="No tiene permisos para modificar inventario de otra sucursal.",
            )
    return inv


# =========================================================================
# CONSULTAS GLOBALES Y DE SUCURSAL
# =========================================================================

@router.get("", response_model=list[schemas.InventarioOut])
def listar_inventario(
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal"),
    producto_id: int | None = Query(None, description="Filtrar por producto"),
    categoria_id: int | None = Query(None, description="Filtrar por categoría de producto"),
    talla_id: int | None = Query(None, description="Filtrar por talla"),
    color_id: int | None = Query(None, description="Filtrar por color"),
    solo_disponibles: bool = Query(False, description="Mostrar solo con stock disponible"),
    solo_agotados: bool = Query(False, description="Mostrar solo productos agotados"),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Consulta de existencias de inventario con múltiples filtros (global o por sucursal)."""
    sucursal_efectiva = _validar_sucursal_usuario(usuario, sucursal_id)
    return service.listar_inventario(
        db=db,
        sucursal_id=sucursal_efectiva,
        producto_id=producto_id,
        categoria_id=categoria_id,
        talla_id=talla_id,
        color_id=color_id,
        solo_disponibles=solo_disponibles,
        solo_agotados=solo_agotados,
    )


@router.get("/resumen", response_model=schemas.ResumenInventario)
def obtener_resumen(
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal (solo admin)"),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Resumen consolidado de indicadores de inventario (global o de sucursal)."""
    sucursal_efectiva = _validar_sucursal_usuario(usuario, sucursal_id)
    return service.resumen_global(db, sucursal_id=sucursal_efectiva)


@router.get("/alertas", response_model=list[schemas.AlertaStock])
def obtener_alertas_stock(
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal (solo admin)"),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Listado de alertas por productos con stock bajo o agotados."""
    sucursal_efectiva = _validar_sucursal_usuario(usuario, sucursal_id)
    return service.alertas_stock_bajo(db, sucursal_id=sucursal_efectiva)


@router.get("/mi-sucursal", response_model=list[schemas.InventarioOut])
def obtener_inventario_mi_sucursal(
    producto_id: int | None = Query(None, description="Filtrar por producto"),
    talla_id: int | None = Query(None, description="Filtrar por talla"),
    color_id: int | None = Query(None, description="Filtrar por color"),
    solo_disponibles: bool = Query(False, description="Mostrar solo con stock disponible"),
    solo_agotados: bool = Query(False, description="Mostrar solo productos agotados"),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Obtiene las existencias de la sucursal asignada al usuario conectado."""
    if usuario.rol == "encargado_sucursal" and not usuario.sucursal_id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="El encargado no tiene una sucursal asignada.",
        )
    sucursal_efectiva = usuario.sucursal_id
    if sucursal_efectiva is None:
        primera = db.query(Sucursal).filter(Sucursal.activa.is_(True)).order_by(Sucursal.id).first()
        if primera:
            sucursal_efectiva = primera.id

    return service.listar_inventario(
        db=db,
        sucursal_id=sucursal_efectiva,
        producto_id=producto_id,
        talla_id=talla_id,
        color_id=color_id,
        solo_disponibles=solo_disponibles,
        solo_agotados=solo_agotados,
    )


@router.get("/movimientos", response_model=list[schemas.MovimientoInventarioOut])
def listar_movimientos(
    sucursal_id: int | None = Query(None, description="Filtrar por sucursal"),
    inventario_id: int | None = Query(None, description="Filtrar por registro de inventario"),
    tipo: str | None = Query(None, description="Filtrar por tipo de movimiento (entrada, salida, ajuste)"),
    limit: int = Query(100, ge=1, le=500, description="Cantidad máxima de movimientos"),
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Historial de movimientos de inventario (entradas, salidas, ajustes)."""
    sucursal_efectiva = _validar_sucursal_usuario(usuario, sucursal_id)
    return service.listar_movimientos(
        db=db,
        sucursal_id=sucursal_efectiva,
        inventario_id=inventario_id,
        tipo=tipo,
        limit=limit,
    )


# =========================================================================
# OPERACIONES DE ESCRITURA / GESTIÓN (CU15)
# =========================================================================

@router.post("", response_model=schemas.InventarioOut, status_code=201)
def crear_inventario(
    data: schemas.InventarioCreate,
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Crea un nuevo registro de inventario con stock inicial para una sucursal."""
    _validar_sucursal_usuario(usuario, data.sucursal_id)
    return service.crear_o_inicializar_inventario(db, data, usuario_id=usuario.id)


@router.post("/movimientos", response_model=schemas.MovimientoInventarioOut, status_code=201)
def registrar_movimiento(
    data: schemas.MovimientoCreate,
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Registra una entrada o salida de mercancía en el inventario de la sucursal."""
    _obtener_y_validar_inventario(db, data.inventario_id, usuario)
    return service.registrar_movimiento(db, data, usuario_id=usuario.id)


@router.post("/ajuste", response_model=schemas.InventarioOut)
def ajustar_stock(
    data: schemas.AjusteStockCreate,
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Ajusta el stock físico de un producto tras auditoría o conteo físico."""
    _obtener_y_validar_inventario(db, data.inventario_id, usuario)
    return service.ajustar_stock(db, data, usuario_id=usuario.id)


@router.patch("/{inventario_id}/stock-minimo", response_model=schemas.InventarioOut)
def actualizar_stock_minimo(
    inventario_id: int,
    data: schemas.StockMinimoUpdate,
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Actualiza el nivel de stock mínimo para alertas en la sucursal."""
    _obtener_y_validar_inventario(db, inventario_id, usuario)
    return service.actualizar_stock_minimo(db, inventario_id, data)


@router.get("/sucursal/{sucursal_id}", response_model=list[schemas.InventarioOut])
def inventario_por_sucursal(
    sucursal_id: int,
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Consulta de inventario para una sucursal específica."""
    _validar_sucursal_usuario(usuario, sucursal_id)
    return service.inventario_por_sucursal(db, sucursal_id)


@router.get("/producto/{producto_id}", response_model=list[schemas.InventarioOut], dependencies=[Depends(admin_only)])
def inventario_por_producto(producto_id: int, db: Session = Depends(get_db)):
    """Consulta de distribución de stock de un producto en todas las sucursales (admin)."""
    return service.inventario_por_producto(db, producto_id)


@router.get("/{inventario_id}", response_model=schemas.InventarioOut)
def obtener_inventario_por_id(
    inventario_id: int,
    usuario: Usuario = Depends(admin_or_encargado),
    db: Session = Depends(get_db),
):
    """Consulta los detalles de un registro de inventario específico."""
    return _obtener_y_validar_inventario(db, inventario_id, usuario)
