FROM alpine:3.23

WORKDIR /app

RUN apk add --no-cache python3 \
  && addgroup -S app \
  && adduser -S app -G app

ENV PYTHONUNBUFFERED=1
ENV SERVICE_NAME=emailservice
ENV SERVICE_PORT=8080

COPY src ./src

USER app

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null "http://localhost:${SERVICE_PORT}/health" || exit 1

CMD ["python3", "src/server.py"]
