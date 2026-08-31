"""Endpoints HTTP del módulo inventario. Registrar en app/main.py."""
from fastapi import APIRouter

router = APIRouter(prefix="/inventario", tags=["inventario"])

# TODO: agregar endpoints, ej.
# @router.get("/")
# def listar(...):
#     ...
