"""Endpoints HTTP del módulo auth. Registrar en app/main.py."""
from fastapi import APIRouter

router = APIRouter(prefix="/auth", tags=["auth"])

# TODO: agregar endpoints, ej.
# @router.get("/")
# def listar(...):
#     ...
