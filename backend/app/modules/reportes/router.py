"""Endpoints HTTP del módulo reportes. Registrar en app/main.py."""
from fastapi import APIRouter

router = APIRouter(prefix="/reportes", tags=["reportes"])

# TODO: agregar endpoints, ej.
# @router.get("/")
# def listar(...):
#     ...
