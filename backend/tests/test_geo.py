"""Pruebas de `app.geo.parse_coordinates` (Taller Semana 14, Fase 4).

Uso (desde `backend/`):
    python -m unittest discover -s tests -v
"""
import unittest

from app.geo import parse_coordinates


class ParseCoordinatesTest(unittest.TestCase):
    def test_coordenadas_validas_como_numeros(self):
        self.assertEqual(
            parse_coordinates(12.35, -76.54),
            {'latitude': 12.35, 'longitude': -76.54},
        )

    def test_coordenadas_validas_como_texto_query_string(self):
        # Así llegan en `GET /rooms/list?lat=..&lng=..`.
        self.assertEqual(
            parse_coordinates('12.35', '-76.54'),
            {'latitude': 12.35, 'longitude': -76.54},
        )

    def test_limites_incluidos(self):
        self.assertIsNotNone(parse_coordinates(90, 180))
        self.assertIsNotNone(parse_coordinates(-90, -180))
        self.assertIsNotNone(parse_coordinates(0, 0))

    def test_falta_un_valor(self):
        self.assertIsNone(parse_coordinates(None, None))
        self.assertIsNone(parse_coordinates(12.35, None))
        self.assertIsNone(parse_coordinates(None, -76.54))

    def test_fuera_de_rango(self):
        self.assertIsNone(parse_coordinates(90.01, 0))
        self.assertIsNone(parse_coordinates(-90.01, 0))
        self.assertIsNone(parse_coordinates(0, 180.01))
        self.assertIsNone(parse_coordinates(0, -180.01))

    def test_texto_no_numerico(self):
        self.assertIsNone(parse_coordinates('abc', '-76.54'))
        self.assertIsNone(parse_coordinates('12.35', ''))

    def test_nan_e_infinito(self):
        self.assertIsNone(parse_coordinates('nan', '0'))
        self.assertIsNone(parse_coordinates('inf', '0'))
        self.assertIsNone(parse_coordinates(0, float('-inf')))

    def test_booleanos_rechazados(self):
        self.assertIsNone(parse_coordinates(True, False))

    def test_tipos_raros_no_lanzan(self):
        self.assertIsNone(parse_coordinates([1], {'a': 1}))


if __name__ == '__main__':
    unittest.main()
