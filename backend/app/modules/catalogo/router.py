"""Endpoints HTTP del módulo Catálogo. Se registra en app/main.py."""
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session

from app.shared.db.session import get_db
from app.modules.catalogo import schemas, service

router = APIRouter(prefix="/catalogo", tags=["catalogo"])


@router.get("/productos", response_model=list[schemas.ProductoOut])
def listar_productos(categoria: str | None = None, db: Session = Depends(get_db)):
    return service.listar_productos(db, categoria)


@router.get("/productos/{producto_id}", response_model=schemas.ProductoOut)
def obtener_producto(producto_id: int, db: Session = Depends(get_db)):
    producto = service.obtener_producto(db, producto_id)
    if not producto:
        raise HTTPException(status_code=404, detail="Producto no encontrado")
    return producto


@router.post("/productos", response_model=schemas.ProductoOut, status_code=201)
def crear_producto(data: schemas.ProductoCreate, db: Session = Depends(get_db)):
    return service.crear_producto(db, data)
