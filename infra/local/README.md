# Local Infrastructure

The Compose file reserves PostgreSQL for later durable-kernel work. It requires
an explicitly supplied local password and binds only to loopback. F01 does not
start containers, create a cloud database, or claim persistence tests passed.

```sh
cp infra/local/.env.example infra/local/.env
# Replace the placeholder locally, then:
docker compose --env-file infra/local/.env -f infra/local/compose.yaml up -d
```

`.env` is ignored and must never be committed.
