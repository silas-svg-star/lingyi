FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata wget \
    && rm -rf /var/lib/apt/lists/*
COPY new-api /new-api
COPY LICENSE NOTICE /licenses/
RUN chmod +x /new-api
EXPOSE 3000
WORKDIR /data
ENTRYPOINT ["/new-api"]
