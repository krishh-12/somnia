import os
from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker

from somnia.models import Base

_engine = None
_session_factory = None


def database_url() -> str:
    return os.environ.get("DATABASE_URL", "sqlite:///somnia2.db")


def get_engine():
    global _engine, _session_factory
    if _engine is None:
        url = database_url()
        kwargs: dict = {"pool_pre_ping": True}
        if url.startswith("sqlite"):
            kwargs = {"connect_args": {"check_same_thread": False}}
        _engine = create_engine(url, **kwargs)
        _session_factory = sessionmaker(bind=_engine, expire_on_commit=False)
    return _engine


def session_factory():
    get_engine()
    return _session_factory


def reset_engine() -> None:
    global _engine, _session_factory
    if _engine is not None:
        _engine.dispose()
    _engine = None
    _session_factory = None


def db_session() -> Iterator[Session]:
    db = session_factory()()
    try:
        yield db
    finally:
        db.close()


def init_db() -> None:
    Base.metadata.create_all(get_engine())
