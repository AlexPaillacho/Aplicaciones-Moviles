from datetime import datetime

from sqlalchemy import Boolean, Column, DateTime, ForeignKey, Integer, String
from sqlalchemy.orm import relationship

from app import db


class User(db.Model):
    __tablename__ = 'users'

    id = Column(Integer, primary_key=True)
    username = Column(String(80), nullable=False)
    email = Column(String(200), unique=True, nullable=False, index=True)
    password_hash = Column(String(255), nullable=False)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)

    def __repr__(self) -> str:
        return f'<User id={self.id} email={self.email}>'


class Room(db.Model):
    __tablename__ = 'rooms'

    id = Column(Integer, primary_key=True)
    name = Column(String(120), nullable=False)
    active = Column(Boolean, default=True, nullable=False, index=True)

    host_id = Column(Integer, ForeignKey('users.id'), nullable=False)
    host = relationship('User', lazy='select')

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    # Se usa como base de comparación para la resolución de conflictos del
    # taller de Semana 12: el cliente guarda el `updated_at` que tenía la
    # sala al momento de encolar una edición offline (`PUT /rooms/<id>`).
    # Si al sincronizar el valor en el servidor ya avanzó, gana el servidor.
    updated_at = Column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    def __repr__(self) -> str:
        return f'<Room id={self.id} name={self.name} active={self.active}>'


class AudioSubmission(db.Model):
    """Persiste cada envío de audio a /rooms/<id>/process-audio y el resultado
    final de la tarea Celery, en vez de dejarlo vivir solo en Redis/Celery
    (que es efímero). Da un 4to recurso CRUD real y una tercera entidad
    para demostrar 3FN con relaciones íntegras (room_id, user_id -> FKs)."""
    __tablename__ = 'audio_submissions'

    id = Column(Integer, primary_key=True)

    room_id = Column(Integer, ForeignKey('rooms.id'), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey('users.id'), nullable=False, index=True)

    task_id = Column(String(64), nullable=False, index=True)
    saved_filename = Column(String(255), nullable=True)

    # PENDING | STARTED | SUCCESS | FAILURE (espeja los estados de Celery)
    status = Column(String(20), nullable=False, default='PENDING', index=True)
    result_json = Column(String(2000), nullable=True)

    created_at = Column(DateTime, default=datetime.utcnow, nullable=False, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False)

    room = relationship('Room', lazy='select')
    user = relationship('User', lazy='select')

    def __repr__(self) -> str:
        return f'<AudioSubmission id={self.id} room_id={self.room_id} status={self.status}>'

