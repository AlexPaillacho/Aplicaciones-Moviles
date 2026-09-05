"""Migración puntual para el taller de Semana 12.

`db.create_all()` (ver README) solo crea tablas que faltan, NO agrega
columnas nuevas a una tabla `rooms` que ya existía. Este script agrega la
columna `updated_at` si hace falta, para no perder los datos que ya
tengas en `dev.db`.

Uso:
    cd backend
    python migrate_add_room_updated_at.py
"""
import sys
from datetime import datetime

from sqlalchemy import text

from app import create_app, db


def main() -> None:
    app = create_app()
    with app.app_context():
        engine = db.engine
        with engine.connect() as conn:
            cols = [row[1] for row in conn.execute(text("PRAGMA table_info(rooms)"))]

            if 'updated_at' in cols:
                print("[MIGRATE] La columna 'updated_at' ya existe en 'rooms'. Nada que hacer.")
                return

            print("[MIGRATE] Agregando columna 'updated_at' a 'rooms'...")
            conn.execute(text("ALTER TABLE rooms ADD COLUMN updated_at DATETIME"))
            # Sembramos las filas existentes con la hora actual, para que
            # tengan una base de comparación válida desde ya.
            now = datetime.utcnow().isoformat(sep=' ')
            conn.execute(text("UPDATE rooms SET updated_at = :now WHERE updated_at IS NULL"),
                         {'now': now})
            conn.commit()
            print("[MIGRATE] Listo. Columna agregada y filas existentes actualizadas.")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"[MIGRATE] Error: {exc}", file=sys.stderr)
        raise
