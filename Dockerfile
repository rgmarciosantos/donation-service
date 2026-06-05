# =============================================================================
# Stage 1: Builder - Compilação da aplicação Go
# =============================================================================
FROM golang:1.26-alpine AS builder

RUN apk add --no-cache ca-certificates git

WORKDIR /build

COPY go.mod go.sum ./

RUN go mod download

# agora o resto do código
COPY . .

# Compila binário estático e otimizado
# CGO_ENABLED=0: binário estático sem dependências C
# -ldflags="-w -s": remove informações de debug (reduz tamanho)
# -trimpath: remove caminhos absolutos do binário (reprodutibilidade)
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -trimpath \
    -ldflags="-w -s" \
    -o donation-service .

# =============================================================================
# Stage 2: Final - Imagem de produção mínima
# =============================================================================
FROM alpine:3.21

# Certificados SSL (necessário para AWS via HTTPS) e wget para healthcheck
RUN apk add --no-cache ca-certificates tzdata wget

# Usuário não-root
RUN addgroup -g 1001 -S appgroup && \
    adduser -u 1001 -S appuser -G appgroup

WORKDIR /app

# Copia binário do stage anterior
COPY --from=builder --chown=appuser:appgroup /build/donation-service .

# Copia scripts SQL (para referência/inicialização do DB)
COPY --chown=appuser:appgroup db/ ./db/

USER appuser

EXPOSE 8082

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8082/health || exit 1

CMD ["./donation-service"]
