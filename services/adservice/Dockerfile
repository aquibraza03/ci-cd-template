FROM alpine:3.23 AS build

WORKDIR /src

RUN apk add --no-cache openjdk21-jdk

COPY src ./src

RUN mkdir -p out \
  && javac -d out $(find src -name "*.java" ! -name "*Test.java")

FROM alpine:3.23

WORKDIR /app

RUN apk add --no-cache openjdk21-jre-headless \
  && addgroup -S app \
  && adduser -S app -G app

ENV SERVICE_NAME=adservice
ENV SERVICE_PORT=9555

COPY --from=build /src/out ./out

USER app

EXPOSE 9555

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null "http://localhost:${SERVICE_PORT}/health" || exit 1

CMD ["java", "-cp", "out", "AdServiceHttp"]
