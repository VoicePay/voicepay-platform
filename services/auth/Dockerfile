FROM python:3.13-slim

WORKDIR /app

RUN apt-get update && apt-get install -y \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN useradd -r -s /bin/false appuser && chown -R appuser:appuser /app

USER appuser

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV NEW_RELIC_CONFIG_FILE=newrelic.ini

EXPOSE 8000

CMD ["sh", "-c", "python manage.py migrate && newrelic-admin run-program gunicorn voicepay.wsgi:application --bind 0.0.0.0:8000 --workers 2 --timeout 120"]
