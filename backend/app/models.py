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

    def __repr__(self) -> str:
        return f'<Room id={self.id} name={self.name} active={self.active}>'

