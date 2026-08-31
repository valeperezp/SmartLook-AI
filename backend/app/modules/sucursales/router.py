"""Endpoints HTTP del módulo sucursales. Registrar en app/main.py."""
from fastapi import APIRouter

router = APIRouter(prefix="/sucursales", tags=["sucursales"])

# TODO: agregar endpoints, ej.
# @router.get("/")
# def listar(...):
#     ...
