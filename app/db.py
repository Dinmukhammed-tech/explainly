"""The database: tables and the connection.

    Subject   one course, for example "Operating Systems"
    Material  one uploaded file of that subject
    Chunk     the text of one slide + its vector, used for search (RAG)
    Topic     one exam question made from a material
    KeyPoint  one idea a full answer must contain
    Attempt   one spoken answer and its check

The topic map is not stored. It is calculated from the attempts, so it can
never get out of sync with what the student really answered.
"""

from datetime import date, datetime, timezone

from pgvector.sqlalchemy import Vector
from sqlalchemy import JSON, Date, DateTime, Float, ForeignKey, Integer, String, Text, create_engine, text
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship, sessionmaker

from . import config

engine = create_engine(config.DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(engine, expire_on_commit=False)


def now() -> datetime:
    return datetime.now(timezone.utc)


class Base(DeclarativeBase):
    pass


class Subject(Base):
    __tablename__ = "subjects"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(120))
    exam_date: Mapped[date | None] = mapped_column(Date)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)

    materials: Mapped[list["Material"]] = relationship(back_populates="subject", cascade="all, delete-orphan")
    topics: Mapped[list["Topic"]] = relationship(back_populates="subject", cascade="all, delete-orphan")


class Material(Base):
    __tablename__ = "materials"

    id: Mapped[int] = mapped_column(primary_key=True)
    subject_id: Mapped[int] = mapped_column(ForeignKey("subjects.id", ondelete="CASCADE"))
    filename: Mapped[str] = mapped_column(String(255))
    slides: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)

    subject: Mapped[Subject] = relationship(back_populates="materials")
    chunks: Mapped[list["Chunk"]] = relationship(back_populates="material", cascade="all, delete-orphan")
    topics: Mapped[list["Topic"]] = relationship(back_populates="material", cascade="all, delete-orphan")


class Chunk(Base):
    __tablename__ = "chunks"

    id: Mapped[int] = mapped_column(primary_key=True)
    material_id: Mapped[int] = mapped_column(ForeignKey("materials.id", ondelete="CASCADE"))
    slide: Mapped[int] = mapped_column(Integer)
    text: Mapped[str] = mapped_column(Text)
    embedding: Mapped[list[float]] = mapped_column(Vector(config.EMBED_DIM))

    material: Mapped[Material] = relationship(back_populates="chunks")


class Topic(Base):
    __tablename__ = "topics"

    id: Mapped[int] = mapped_column(primary_key=True)
    subject_id: Mapped[int] = mapped_column(ForeignKey("subjects.id", ondelete="CASCADE"))
    material_id: Mapped[int] = mapped_column(ForeignKey("materials.id", ondelete="CASCADE"))
    title: Mapped[str] = mapped_column(String(200))
    question: Mapped[str] = mapped_column(Text)

    subject: Mapped[Subject] = relationship(back_populates="topics")
    material: Mapped[Material] = relationship(back_populates="topics")
    key_points: Mapped[list["KeyPoint"]] = relationship(
        back_populates="topic", cascade="all, delete-orphan", order_by="KeyPoint.id"
    )
    attempts: Mapped[list["Attempt"]] = relationship(
        back_populates="topic", cascade="all, delete-orphan", order_by="Attempt.id"
    )


class KeyPoint(Base):
    __tablename__ = "key_points"

    id: Mapped[int] = mapped_column(primary_key=True)
    topic_id: Mapped[int] = mapped_column(ForeignKey("topics.id", ondelete="CASCADE"))
    point: Mapped[str] = mapped_column(Text)
    label: Mapped[str] = mapped_column(String(80), default="")
    slide: Mapped[int | None] = mapped_column(Integer)

    topic: Mapped[Topic] = relationship(back_populates="key_points")


class Attempt(Base):
    __tablename__ = "attempts"

    id: Mapped[int] = mapped_column(primary_key=True)
    topic_id: Mapped[int] = mapped_column(ForeignKey("topics.id", ondelete="CASCADE"))
    transcript: Mapped[str] = mapped_column(Text)
    mastery: Mapped[float] = mapped_column(Float)  # 0..1, share of key points named
    result: Mapped[dict] = mapped_column(JSON)  # the full check, as shown to the student
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=now)

    topic: Mapped[Topic] = relationship(back_populates="attempts")


def init_db() -> None:
    """Create the pgvector extension and the tables if they are not there yet."""
    with engine.begin() as conn:
        conn.execute(text("CREATE EXTENSION IF NOT EXISTS vector"))
    Base.metadata.create_all(engine)


def get_session():
    """FastAPI dependency: one database session per request."""
    with SessionLocal() as session:
        yield session
