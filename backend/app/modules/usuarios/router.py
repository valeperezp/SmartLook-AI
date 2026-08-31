"""Endpoints HTTP del módulo usuarios. Registrar en app/main.py."""
from fastapi import APIRouter

router = APIRouter(prefix="/usuarios", tags=["usuarios"])

# TODO: agregar endpoints, ej.
# @router.get("/")
# def listar(...):
#     ...
