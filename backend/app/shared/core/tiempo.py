"""Zona horaria de la operación (Bolivia, UTC-4 fijo, sin horario de verano).

La base de datos y el servidor trabajan en UTC; cualquier texto pensado para
que lo lea una persona (reportes, respuestas del asistente de IA) debe convertir
a esta zona antes de mostrarse.
"""
from zoneinfo import ZoneInfo

ZONA_HORARIA_LOCAL = ZoneInfo("America/La_Paz")
