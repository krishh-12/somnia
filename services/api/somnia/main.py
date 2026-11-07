from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from somnia import __version__
from somnia.db import init_db, session_factory
from somnia.pipeline import ensure_ready
from somnia.routes import router


def create_app() -> FastAPI:
    init_db()
    with session_factory()() as db:
        ensure_ready(db)
    app = FastAPI(title="Somnia", version=__version__)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.include_router(router)

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok", "service": "somnia", "version": __version__}

    return app
