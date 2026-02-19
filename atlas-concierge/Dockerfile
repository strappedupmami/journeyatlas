FROM rust:1.82-bookworm AS builder
WORKDIR /app

COPY Cargo.toml Cargo.lock* ./
COPY crates ./crates
COPY kb ./kb
COPY config ./config
COPY migrations ./migrations

RUN cargo build --release -p atlas-api

FROM debian:bookworm-slim AS runtime
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=builder /app/target/release/atlas-api /usr/local/bin/atlas-api
COPY --from=builder /app/kb ./kb
COPY --from=builder /app/config ./config
COPY --from=builder /app/migrations ./migrations

ENV ATLAS_BIND=0.0.0.0:8080
ENV ATLAS_KB_ROOT=kb

EXPOSE 8080
CMD ["atlas-api"]
