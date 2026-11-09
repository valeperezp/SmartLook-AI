"""Endpoints de cambios y devoluciones (CU11)."""
from fastapi import APIRouter, Depends, File, Query, Request, UploadFile
from fastapi.concurrency import run_in_threadpool
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.bitacora import service as bitacora
from app.modules.devoluciones import schemas, service
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db

router = APIRouter(prefix="/devoluciones", tags=["devoluciones"])

personal_de_venta = require_roles(*service.ROLES_DEVOLUCION)
solo_admin = require_roles("administrador")
solo_cliente = require_roles("cliente")


@router.get("/configuracion", response_model=schemas.ConfiguracionOut)
def ver_configuracion(db: Session = Depends(get_db), usuario: Usuario = Depends(personal_de_venta)):
    """Días que una venta admite cambios y devoluciones en esta empresa (7 por defecto)."""
    return {"plazo_dias": service.plazo_dias(db, usuario.empresa_id)}


@router.put("/configuracion", response_model=schemas.ConfiguracionOut)
def cambiar_configuracion(
    data: schemas.ConfiguracionIn,
    request: Request,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(solo_admin),
):
    """El administrador define el plazo (en días) de SU empresa."""
    dias = service.guardar_plazo(db, usuario.empresa_id, data.plazo_dias)
    bitacora.registrar(db, "devolucion.plazo", f"Plazo de cambios y devoluciones: {dias} días", usuario=usuario, request=request)
    db.commit()
    return {"plazo_dias": dias}


@router.get("/buscar", response_model=schemas.VentaDevolvibleOut)
def buscar_venta(
    q: str = Query(..., description="Número de ticket (123 o #123) o UUID / recibo de la venta"),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(personal_de_venta),
):
    """Busca la venta y devuelve sus prendas con cuántas se pueden todavía devolver y cuánto plazo queda."""
    return service.buscar_venta(db, usuario, q)


@router.post("", response_model=schemas.DevolucionOut, status_code=201)
def registrar_devolucion(
    data: schemas.DevolucionCreate,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(personal_de_venta),
):
    """Registra un cambio o una devolución. El servidor valida el plazo, las cantidades y el stock; si algo falla no
    se guarda nada (400 con el motivo)."""
    return service.registrar_devolucion(db, usuario, data)


# ---------------------------------------------------------------------------------------------------------------
# Reembolsos: devolución de DINERO de un pedido (reserva o venta) cancelado
# ---------------------------------------------------------------------------------------------------------------

@router.post("/reembolsos", response_model=schemas.ReembolsoOut)
def pedir_reembolso(
    data: schemas.ReembolsoSolicitud,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(solo_cliente),
):
    """El cliente pide el reembolso de SU pedido cancelado. Si ya lo pidió devuelve el mismo (idempotente)."""
    return service.solicitar_reembolso(db, usuario, data.reserva_id, data.venta_id)


@router.get("/mis-reembolsos", response_model=list[schemas.ReembolsoOut])
def mis_reembolsos(db: Session = Depends(get_db), usuario: Usuario = Depends(solo_cliente)):
    """Los reembolsos del cliente autenticado."""
    return service.listar_mis_reembolsos(db, usuario)


@router.get("/reembolsos", response_model=list[schemas.ReembolsoDetalleOut])
def listar_reembolsos(
    estado: str | None = Query(None, description="pendiente | reembolsado"),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(personal_de_venta),
):
    """Reembolsos de la empresa (cajero y encargado, solo los de su sucursal), con la URL del QR que subió el cliente."""
    return service.listar_reembolsos(db, usuario, estado)


@router.post("/reembolsos/procesar", response_model=schemas.ReembolsoDetalleOut)
def procesar_reembolso(
    data: schemas.ReembolsoSolicitud,
    request: Request,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(personal_de_venta),
):
    """Marca el reembolso como hecho (ya se le transfirió al cliente): el pedido pasa a `reembolsada`."""
    return service.procesar_reembolso(db, usuario, data.reserva_id, data.venta_id, request=request)


@router.post("/{reembolso_id}/qr", response_model=schemas.ReembolsoOut)
async def subir_qr_devolucion(
    reembolso_id: int,
    archivo: UploadFile = File(...),
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(solo_cliente),
):
    """El cliente sube su QR bancario para recibir el reembolso (PNG, JPG o WEBP). Solo el dueño del reembolso."""
    contenido = await archivo.read(service.MAX_QR_BYTES + 1)  # nunca se lee más de lo permitido
    return await run_in_threadpool(service.subir_qr, db, usuario, reembolso_id, contenido)
