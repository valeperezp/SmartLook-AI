"""Endpoints HTTP del módulo ia. Registrar en app/main.py."""
from fastapi import APIRouter

router = APIRouter(prefix="/ia", tags=["ia"])

# TODO: agregar endpoints, ej.
# @router.get("/")
# def listar(...):
#     ...
