"""Validación de coordenadas opcionales (Taller Semana 14, Fase 4).

La app móvil puede mandar la ubicación APROXIMADA del usuario (ya
redondeada a ~1 km en el cliente) al listar o crear salas, para una
futura ordenación por cercanía. Es un dato OPCIONAL: si falta o viene
mal formado, la petición se procesa igual, simplemente sin ubicación.

Vive en su propio módulo, sin importar Flask ni SQLAlchemy, para poder
probarlo de forma aislada (ver `tests/test_geo.py`).
"""
from typing import Optional


def parse_coordinates(latitude, longitude) -> Optional[dict]:
    """Devuelve ``{'latitude': float, 'longitude': float}`` si ambos
    valores son coordenadas válidas; en cualquier otro caso ``None``.

    Válido significa: ambos presentes, convertibles a número finito,
    latitud en [-90, 90] y longitud en [-180, 180]. Los booleanos se
    rechazan a propósito (``float(True)`` daría 1.0 sin ser una
    coordenada). Un valor inválido NO lanza excepción: se ignora, porque
    la ubicación es una pista opcional y nunca debe hacer fallar el
    listado ni la creación de una sala.
    """
    if latitude is None or longitude is None:
        return None
    if isinstance(latitude, bool) or isinstance(longitude, bool):
        return None

    try:
        lat = float(latitude)
        lng = float(longitude)
    except (TypeError, ValueError):
        return None

    # NaN e infinitos no cumplen estas comparaciones, así que también
    # quedan fuera.
    if not (-90.0 <= lat <= 90.0 and -180.0 <= lng <= 180.0):
        return None

    return {'latitude': lat, 'longitude': lng}
