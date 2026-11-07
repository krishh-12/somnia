FROM python:3.12-slim-bookworm
WORKDIR /app
COPY services/api /app
RUN pip install --no-cache-dir .
EXPOSE 8000
CMD ["uvicorn", "somnia.main:create_app", "--factory", "--host", "0.0.0.0", "--port", "8000"]
