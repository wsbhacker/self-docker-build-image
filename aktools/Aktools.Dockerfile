FROM python:3.13-slim-bullseye

RUN pip install --upgrade pip

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY aktools-src /aktools-src
RUN pip install --no-cache-dir --no-deps /aktools-src

WORKDIR /usr/local/lib/python3.13/site-packages/aktools
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "main:app", "-k", "uvicorn.workers.UvicornWorker"]
