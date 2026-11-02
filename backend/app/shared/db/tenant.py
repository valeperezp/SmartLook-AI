"""Helpers multi-empresa (tenant) para las consultas de los módulos.

Regla: un registro de otra empresa se trata como si no existiera (404),
así no se filtra ni siquiera su existencia.
"""
from fastapi import HTTPException
from sqlalchemy.orm import Query, Session


def de_empresa(query: Query, modelo, empresa_id: int) -> Query:
    """Filtra una consulta de `modelo` (que tiene columna empresa_id) por empresa."""
    return query.filter(modelo.empresa_id == empresa_id)


def asegurar_de_empresa(db: Session, modelo, registro_id: int | None, empresa_id: int, etiqueta: str):
    """Valida que `registro_id` exista y sea de la empresa. Devuelve el registro (o None si el id es None)."""
    if registro_id is None:
        return None
    registro = (
        db.query(modelo).filter(modelo.id == registro_id, modelo.empresa_id == empresa_id).first()
    )
    if registro is None:
        raise HTTPException(status_code=404, detail=f"{etiqueta} no encontrada en tu empresa")
    return registro
