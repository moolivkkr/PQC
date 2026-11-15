FROM python:3.13-slim-trixie
RUN useradd -r -u 10001 app
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
# Fails the build if this image's OpenSSL cannot do ML-KEM.
RUN python -c "import ssl,sys; sys.exit(0 if ssl.OPENSSL_VERSION_INFO >= (3,5) else 'OpenSSL < 3.5')"
USER app
EXPOSE 8443
CMD ["gunicorn", "-c", "gunicorn.conf.py", "app:wsgi"]
