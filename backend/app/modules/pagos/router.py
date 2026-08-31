"""Endpoints HTTP del módulo pagos. Registrar en app/main.py."""
from fastapi import APIRouter

router = APIRouter(prefix="/pagos", tags=["pagos"])

# TODO: agregar endpoints, ej.
# @router.get("/")
# def listar(...):
#     ...
