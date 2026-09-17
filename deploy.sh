#!/usr/bin/env bash

set -e

TRAEFIK_FILE="docker-compose.traefik.yml"
APPS_FILE="docker-compose.apps.yml"
NETWORK_NAME="traefik-public"

log_info() { echo -e "\033[1;34m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[1;32m[SUCCESS]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }
log_error() { echo -e "\033[1;31m[ERROR]\033[0m $1"; exit 1; }

# --- DETECT THE CORRECT COMPOSE COMMAND NATIVELY ---
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif docker-compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    log_error "Neither 'docker compose' nor 'docker-compose' was found on your system. Please install the Docker Compose plugin."
fi

echo "=================================================="
echo "      AUTOMATED DEPLOYMENT WITH HEALTHCHECKS      "
echo "=================================================="

# 1. Cleanup
log_info "Using compose tool: $COMPOSE_CMD"
log_info "Tearing down existing components..."
$COMPOSE_CMD -f "$APPS_FILE" down --remove-orphans || true
$COMPOSE_CMD -f "$TRAEFIK_FILE" down --remove-orphans || true

if docker network inspect "$NETWORK_NAME" >/dev/null 2>&1; then
    docker network rm "$NETWORK_NAME" >/dev/null
fi

log_info "Creating fresh external network: $NETWORK_NAME"
docker network create "$NETWORK_NAME"

# 2. Deploy infrastructure
log_info "Launching Traefik proxy..."
$COMPOSE_CMD -f "$TRAEFIK_FILE" up -d

log_info "Launching application cluster..."
$COMPOSE_CMD -f "$APPS_FILE" up -d --build

# 3. Dynamic Health Verification Loop
log_info "Waiting for application containers to clear initialization periods..."
TIMEOUT=30
ELAPSED=0

while true; do
    STATUS1=$(docker inspect --format='{{.State.Health.Status}}' my-app1 2>/dev/null || echo "starting")
    STATUS2=$(docker inspect --format='{{.State.Health.Status}}' my-app2 2>/dev/null || echo "starting")

    if [ "$STATUS1" = "healthy" ] && [ "$STATUS2" = "healthy" ]; then
        log_success "All application nodes passed health checks safely."
        break
    fi

    if [ "$STATUS1" = "unhealthy" ] || [ "$STATUS2" = "unhealthy" ]; then
        log_error "Deployment failed! One or more application nodes reported critical health states."
    fi

    if [ $ELAPSED -ge $TIMEOUT ]; then
        log_error "Deployment timed out waiting for nodes to become healthy."
    fi

    echo -n "."
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# 4. Success State Summary
echo -e "\n=================================================="
log_success "Demo Environment Active!"
echo "=================================================="
log_info "Verification targets:"
echo "  -> Public Route: curl -H \"Host: dynpage.localhost\" http://localhost/page1"
echo "  -> Blocked Route (Should 403): curl -I -H \"Host: dynpage.localhost\" http://localhost/admin"
echo "=================================================="

