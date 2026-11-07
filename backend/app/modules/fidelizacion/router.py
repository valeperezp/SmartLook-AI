"""Endpoints de fidelización (CU17): saldo de puntos y regla de la empresa."""
from fastapi import APIRouter, Depends, Request
from sqlalchemy.orm import Session

from app.modules.auth.service import require_roles
from app.modules.bitacora import service as bitacora
from app.modules.fidelizacion import schemas, service
from app.modules.usuarios.models import Usuario
from app.shared.db.session import get_db

router = APIRouter(prefix="/clientes", tags=["fidelizacion"])

solo_cliente = require_roles("cliente")
personal_de_venta = require_roles("cajero", "encargado_sucursal", "administrador")
solo_admin = require_roles("administrador")


@router.get("/mis-puntos", response_model=schemas.MisPuntos)
def mis_puntos(db: Session = Depends(get_db), usuario: Usuario = Depends(solo_cliente)):
    """Saldo de puntos del cliente logueado y la regla de su empresa (cuánto descuenta cada punto)."""
    return service.mis_puntos(db, usuario)


@router.get("/regla-puntos", response_model=schemas.ReglaPuntosOut)
def ver_regla(db: Session = Depends(get_db), usuario: Usuario = Depends(personal_de_venta)):
    return {"valor_punto_centavos": service.valor_punto_centavos(db, usuario.empresa_id)}


@router.put("/regla-puntos", response_model=schemas.ReglaPuntosOut)
def cambiar_regla(
    data: schemas.ReglaPuntosIn,
    request: Request,
    db: Session = Depends(get_db),
    usuario: Usuario = Depends(solo_admin),
):
    """El administrador define cuánto vale un punto en SU empresa (centavos)."""
    valor = service.guardar_regla(db, usuario.empresa_id, data.valor_punto_centavos)
    bitacora.registrar(db, "fidelizacion.regla", f"Valor del punto: {valor} centavos", usuario=usuario, request=request)
    db.commit()
    return {"valor_punto_centavos": valor}


@router.get("/{cliente_id}/puntos", response_model=schemas.MisPuntos)
def puntos_de_cliente(cliente_id: int, db: Session = Depends(get_db), usuario: Usuario = Depends(personal_de_venta)):
    """Saldo de un cliente de la misma empresa: el cajero lo consulta al cobrar para ofrecer el canje."""
    return service.puntos_de_cliente(db, usuario.empresa_id, cliente_id)
