# donation-service (Go)

⚡ **HOT PATH / Caminho Crítico** da plataforma SolidaryTech. Responsável pelo
**processamento de doações**, persistência no PostgreSQL e publicação de
eventos assíncronos no AWS SQS para downstream (notificações, analytics, etc.).

> Este é o serviço central da estratégia de SRE e DR. Todos os SLOs, alertas
> AIOps e o plano de continuidade de negócios (PCN) são definidos em torno dele.

## 🧱 Stack

| Item | Valor |
|---|---|
| Linguagem | Go 1.21 |
| Banco de Dados | PostgreSQL 15 |
| Mensageria | AWS SQS |
| Porta | `8082` |

## 📦 Pré-requisitos (execução isolada)

- Go 1.21+
- PostgreSQL 15 (local ou container)
- Fila SQS (AWS real ou LocalStack)

## 🔐 Variáveis de Ambiente

| Variável | Obrigatória | Descrição | Exemplo |
|---|---|---|---|
| `DATABASE_URL` | ✅ | String de conexão PostgreSQL | `postgres://user:pass@localhost:5432/donation_db?sslmode=disable` |
| `AWS_REGION` | ✅ | Região AWS | `us-east-1` |
| `AWS_SQS_URL` | ✅ | URL completa da fila SQS | `https://sqs.us-east-1.amazonaws.com/123/solidary-donations` |
| `AWS_ACCESS_KEY_ID` | ✅ | Credencial AWS | `AKIA...` ou `dummy` (LocalStack) |
| `AWS_SECRET_ACCESS_KEY` | ✅ | Credencial AWS | `...` ou `dummy` (LocalStack) |
| `AWS_ENDPOINT_URL` | ❌ | **Aponta para LocalStack** quando definido | `http://localstack:4566` |
| `PORT` | ❌ | Porta HTTP (padrão `8082`) | `8082` |

> 💡 Se `AWS_ENDPOINT_URL` estiver definido, o serviço configura o SDK para
> apontar para LocalStack. Em produção AWS, **deixe vazio** — o SDK usa o
> endpoint padrão de cada região.

## 🚀 Executando localmente (sem Docker)

```bash
# 1. Criar o banco e tabela
psql -U postgres -c "CREATE DATABASE donation_db;"
psql -U postgres -d donation_db -f db/init.sql

# 2. Definir variáveis
export DATABASE_URL="postgres://postgres:postgres@localhost:5432/donation_db?sslmode=disable"
export AWS_REGION=us-east-1
export AWS_SQS_URL="http://localhost:4566/000000000000/solidary-donations"
export AWS_ENDPOINT_URL="http://localhost:4566"
export AWS_ACCESS_KEY_ID=dummy
export AWS_SECRET_ACCESS_KEY=dummy

# 3. Rodar
go mod tidy
go run .
```

> **Recomendado:** use o `docker-compose` da raiz do projeto.

## 🔌 Endpoints

### `GET /health`

```bash
curl http://localhost:8082/health
# → {"status":"ok","service":"donation-service"}
```

### `POST /donations` ⚡

Cria uma doação, persiste no PostgreSQL e dispara evento no SQS de forma
assíncrona (goroutine — não bloqueia a resposta).

**Request:**
```bash
curl -X POST http://localhost:8082/donations \
  -H "Content-Type: application/json" \
  -d '{
    "ngo_id": 1,
    "amount": 150.50,
    "donor_name": "João Silva"
  }'
```

**Resposta (201):**
```json
{
  "id": 1,
  "ngo_id": 1,
  "amount": 150.50,
  "donor_name": "João Silva",
  "status": "APPROVED",
  "created_at": "2026-05-27T15:30:00Z"
}
```

> ℹ️ O status é fixado em `APPROVED` (simulação de gateway de pagamento).

### `GET /donations`

Lista todas as doações.

```bash
curl http://localhost:8082/donations
```

## 📨 Evento publicado no SQS

Para cada doação criada, o serviço publica uma mensagem na fila com o payload
JSON completo da doação. Esse evento é consumido por workers downstream
(analytics, notificações, integrações).

```json
{
  "id": 1,
  "ngo_id": 1,
  "amount": 150.50,
  "donor_name": "João Silva",
  "status": "APPROVED",
  "created_at": "2026-05-27T15:30:00Z"
}
```

## 🐳 Imagem Docker

```bash
docker build -t solidary/donation-service:local .
docker run --rm -p 8082:8082 \
  -e DATABASE_URL="..." \
  -e AWS_SQS_URL="..." \
  solidary/donation-service:local
```

**Características da imagem:**
- Multi-stage com `golang:1.21-alpine` → `alpine:3.19` final
- Binário estático (`CGO_ENABLED=0`) com `-ldflags="-w -s"` (sem debug info)
- Imagem final < 25 MB
- Usuário não-root (UID 1001)
- `HEALTHCHECK` embutido

## ⚠️ Notas sobre as dependências

**Migração para AWS SDK Go v2 (mai/2026):** o código original do hackathon
usava `github.com/aws/aws-sdk-go` (v1), que entrou em **end-of-support em
31/jul/2025**. Migramos para `github.com/aws/aws-sdk-go-v2`, que é o padrão
atual e ativamente mantido pela AWS. As mudanças foram:

- `session.NewSession(...)` → `config.LoadDefaultConfig(ctx, ...)`
- `sqs.New(sess)` → `sqs.NewFromConfig(cfg, opts...)`
- Endpoint LocalStack agora vai em `o.BaseEndpoint` nas opções do client
- Todas as chamadas de API agora recebem `context.Context` (boa prática)

**pgx atualizado para v5:** subimos de `pgx/v4` (com bug histórico de
declaração no `go.mod`) para `pgx/v5` (versão atual estável).

**`go.mod` enxuto:** mantemos apenas dependências **diretas**. O `go mod tidy`
durante o build do Docker resolve transitivas e gera `go.sum`.
