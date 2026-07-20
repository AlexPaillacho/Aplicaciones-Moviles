import sys

from werkzeug.security import generate_password_hash

from app import create_app, db
from app.models import Room, User


def main():
    app = create_app()

    with app.app_context():
        # 1) Usuario de prueba (solo si no existe ya, buscando por email)
        email = "alex@example.com"
        user = User.query.filter_by(email=email).first()

        if user is None:
            user = User(
                username="alex",
                email=email,
                password_hash=generate_password_hash("123456"),
            )
            db.session.add(user)
            db.session.commit()
            print(
                f"[SEED] Usuario creado: username={user.username}, email={user.email}"
            )
        else:
            print(
                f"[SEED] Usuario ya existía: username={user.username}, email={user.email}"
            )

        # 2) Salas de prueba (solo si Room está vacía)
        rooms_count = Room.query.count()
        if rooms_count > 0:
            print(
                f"[SEED] Ya existen salas en BD (count={rooms_count}). No se crean nuevas."
            )
            return

        rooms_data = [
            {"name": "Room 1 - Practice", "active": True},
            {"name": "Room 2 - Listening", "active": True},
            {"name": "Room 3 - Conversation", "active": True},
        ]

        for rd in rooms_data:
            room = Room(
                name=rd["name"],
                active=rd["active"],
                host_id=user.id,
            )
            db.session.add(room)

        db.session.commit()

        created_rooms = Room.query.count()
        print(f"[SEED] Salas creadas: count={created_rooms}")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"[SEED] Error: {exc}", file=sys.stderr)
        raise

