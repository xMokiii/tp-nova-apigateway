FROM python:3.12-slim

# Pas de fichiers .pyc (système de fichiers en lecture seule) et logs non bufferisés
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Utilisateur non privilégié
RUN groupadd --system app && useradd --system --gid app --no-create-home app

# Dépendances installées sans conserver le cache pip
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

USER app

EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)" || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
