#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECTS_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TEMPLATE_DOCKER_DIR="${SCRIPT_DIR}/docker"

if [ ! -d "${TEMPLATE_DOCKER_DIR}" ]; then
  echo "Template docker directory not found in ${TEMPLATE_DOCKER_DIR}" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "git is required on the host" >&2
  exit 1
fi

MASTER_NETWORK="shared_network"
MYSQL_CONTAINER="master-db"
MYSQL_ROOT_PASSWORD="123"
POSTGRES_CONTAINER="master-postgres"
POSTGRES_SUPERUSER="postgres"
POSTGRES_PASSWORD="postgres"
REDIS_HOST="master-redis"

while true; do
  printf "Project source ([1] create fresh Laravel / [2] clone existing repo) [1]: "
  read -r SOURCE_CHOICE
  SOURCE_CHOICE=${SOURCE_CHOICE:-1}
  case "${SOURCE_CHOICE}" in
    1|2) ;;
    *)
      echo "Invalid source choice" >&2
      continue
      ;;
  esac

  read -rp "Project directory name (e.g. blog-app): " PROJECT_SLUG
  PROJECT_SLUG=${PROJECT_SLUG:-laravel-app}
  PROJECT_DIR="${PROJECTS_ROOT}/${PROJECT_SLUG}"

  REPO_SSH_URL=""
  if [ "${SOURCE_CHOICE}" = "2" ]; then
    read -rp "Repository SSH URL (e.g. git@repo.wbpo.online:myzones/my-zone.git): " REPO_SSH_URL
    if [ -z "${REPO_SSH_URL}" ]; then
      echo "Repository SSH URL is required for clone mode" >&2
      continue
    fi
  fi

  read -rp "Subdomain for Traefik (e.g. blog): " TRAEFIK_SUBDOMAIN
  TRAEFIK_SUBDOMAIN=${TRAEFIK_SUBDOMAIN:-${PROJECT_SLUG}}
  APP_HOST="${TRAEFIK_SUBDOMAIN}.localhost"

  printf "Database engine ([1] mysql / [2] pgsql) [1]: "
  read -r DB_CHOICE
  case "${DB_CHOICE:-1}" in
    1)
      DB_DRIVER="mysql"
      DB_HOST="${MYSQL_CONTAINER}"
      DB_PORT="3306"
      DB_USER="root"
      DB_PASS="${MYSQL_ROOT_PASSWORD}"
      ;;
    2)
      DB_DRIVER="pgsql"
      DB_HOST="${POSTGRES_CONTAINER}"
      DB_PORT="5432"
      DB_USER="${POSTGRES_SUPERUSER}"
      DB_PASS="${POSTGRES_PASSWORD}"
      ;;
    *)
      echo "Invalid choice" >&2
      continue
      ;;
   esac

  read -rp "Database name [${PROJECT_SLUG//-/_}]: " DB_NAME
  DB_NAME=${DB_NAME:-${PROJECT_SLUG//-/_}}

  cat <<SUMMARY

Configuration:
  Source mode: $( [ "${SOURCE_CHOICE}" = "1" ] && echo "create fresh laravel" || echo "clone repository" )
  Project slug: ${PROJECT_SLUG}
  Repository URL: ${REPO_SSH_URL:-n/a}
  Subdomain: ${TRAEFIK_SUBDOMAIN}
  App host: ${APP_HOST}
  Project directory: ${PROJECT_DIR}
  DB driver: ${DB_DRIVER}
  DB host: db
  DB port: ${DB_PORT}
  DB name: ${DB_NAME}
  DB username: ${DB_USER}
  DB password: 123
SUMMARY

  read -rp "Proceed with this configuration? [y/N]: " CONFIRM
  case "${CONFIRM}" in
    [Yy]*)
      break
      ;;
    *)
      read -rp "Try again with new values? [Y/n]: " RETRY
      case "${RETRY}" in
        [Nn]*)
          echo "Aborting setup."
          exit 1
          ;;
        *)
          continue
          ;;
      esac
      ;;
  esac
done

if [ -d "${PROJECT_DIR}" ]; then
  echo "Directory ${PROJECT_DIR} already exists" >&2
  exit 1
fi

if ! docker network inspect "${MASTER_NETWORK}" >/dev/null 2>&1; then
  docker network create "${MASTER_NETWORK}" >/dev/null
fi

if [ "${SOURCE_CHOICE}" = "1" ]; then
  if ! command -v composer >/dev/null 2>&1; then
    echo "composer is required on the host for create mode" >&2
    exit 1
  fi
  composer create-project laravel/laravel "${PROJECT_DIR}"
else
  git clone "${REPO_SSH_URL}" "${PROJECT_DIR}"
fi

pushd "${PROJECT_DIR}" >/dev/null

cat > docker-compose.yml <<'COMPOSE'
name: "%PROJECT_NAME%"
services:
  php:
    extra_hosts:
      - "host.docker.internal:host-gateway"
    build:
      context: .
      dockerfile: docker/php/Dockerfile
    container_name: "%PROJECT_NAME%_php"
    volumes:
      - ./:/var/www/html
    networks:
      - shared_network
  nginx:
    build:
      context: .
      dockerfile: docker/nginx/Dockerfile
    container_name: "%PROJECT_NAME%_nginx"
    depends_on:
      - php
    volumes:
      - ./:/var/www/html
    networks:
      - shared_network
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.%TRAEFIK_ROUTER%.rule=Host(`%APP_HOST%`)"
      - "traefik.http.routers.%TRAEFIK_ROUTER%.entrypoints=web"
      - "traefik.http.services.%TRAEFIK_ROUTER%.loadbalancer.server.port=80"
networks:
  shared_network:
    external: true
COMPOSE

perl -0pi -e "s/%PROJECT_NAME%/${PROJECT_SLUG}/g; s/%TRAEFIK_ROUTER%/${PROJECT_SLUG//-/_}/g; s/%APP_HOST%/${APP_HOST}/g" docker-compose.yml

mkdir -p docker/nginx docker/php
cp "${TEMPLATE_DOCKER_DIR}/nginx/Dockerfile" docker/nginx/Dockerfile
cp "${TEMPLATE_DOCKER_DIR}/nginx/default.conf" docker/nginx/default.conf
cp "${TEMPLATE_DOCKER_DIR}/php/Dockerfile" docker/php/Dockerfile
cp "${TEMPLATE_DOCKER_DIR}/php/php.ini" docker/php/php.ini
cp "${TEMPLATE_DOCKER_DIR}/php/start-container" docker/php/start-container
cp "${TEMPLATE_DOCKER_DIR}/php/supervisord.conf" docker/php/supervisord.conf
chmod +x docker/php/start-container

cp .env.example .env

perl -0pi -e "s/^APP_URL=.*/APP_URL=http:\/\/${APP_HOST}/m" .env
perl -0pi -e "s/^DB_CONNECTION=.*/DB_CONNECTION=${DB_DRIVER}/m" .env
perl -0pi -e "s/^#?\s*DB_HOST=.*/DB_HOST=db/m" .env
perl -0pi -e "s/^#?\s*DB_PORT=.*/DB_PORT=${DB_PORT}/m" .env
perl -0pi -e "s/^#?\s*DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/m" .env
perl -0pi -e "s/^#?\s*DB_USERNAME=.*/DB_USERNAME=${DB_USER}/m" .env
perl -0pi -e "s/^#?\s*DB_PASSWORD=.*/DB_PASSWORD=123/m" .env
perl -0pi -e "s/^REDIS_HOST=.*/REDIS_HOST=${REDIS_HOST}/m" .env

popd >/dev/null

if [ "${DB_DRIVER}" = "mysql" ]; then
  docker exec -i "${MYSQL_CONTAINER}" mysql -uroot -p"${MYSQL_ROOT_PASSWORD}" \
    -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
else
  docker exec -i "${POSTGRES_CONTAINER}" psql -U "${POSTGRES_SUPERUSER}" \
    -c "SELECT 'CREATE DATABASE ${DB_NAME}' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname='${DB_NAME}')\\gexec;"
fi

pushd "${PROJECT_DIR}" >/dev/null
docker compose build php
docker compose run --rm php composer install
docker compose run --rm php php artisan key:generate
docker compose run --rm php php artisan migrate
docker compose up -d
popd >/dev/null

echo "Project ${PROJECT_SLUG} created in ${PROJECT_DIR}"
echo "Add \"${APP_HOST} 127.0.0.1\" to /etc/hosts and run: docker compose up -d"

cd "${PROJECT_DIR}"
