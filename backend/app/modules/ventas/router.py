"""Endpoints HTTP del módulo ventas. Registrar en app/main.py."""
from fastapi import APIRouter

router = APIRouter(prefix="/ventas", tags=["ventas"])

# TODO: agregar endpoints, ej.
# @router.get("/")
# def listar(...):
#     ...
