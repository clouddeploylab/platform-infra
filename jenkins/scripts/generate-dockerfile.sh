#!/bin/bash
set -e

FRAMEWORK=$1
TEMPLATES_DIR=$2/../docker/dockerfiles

if [ -f "Dockerfile" ]; then
    echo "Dockerfile already exists — skipping generation."
    exit 0
fi

echo "Generating Dockerfile for framework: ${FRAMEWORK}"

case "$FRAMEWORK" in
    nextjs)
        cp "${TEMPLATES_DIR}/Dockerfile.nextjs" Dockerfile ;;
    nodejs)
        cp "${TEMPLATES_DIR}/Dockerfile.nodejs" Dockerfile ;;
    springboot)
        cp "${TEMPLATES_DIR}/Dockerfile.springboot" Dockerfile ;;
    gradle)
        cp "${TEMPLATES_DIR}/Dockerfile.gradle" Dockerfile ;;
    go)
        cp "${TEMPLATES_DIR}/Dockerfile.go" Dockerfile ;;
    fastapi)
        cp "${TEMPLATES_DIR}/Dockerfile.fastapi" Dockerfile ;;
    python)
        cp "${TEMPLATES_DIR}/Dockerfile.python" Dockerfile ;;
    static)
        cp "${TEMPLATES_DIR}/Dockerfile.static" Dockerfile ;;
    *)
        cp "${TEMPLATES_DIR}/Dockerfile.static" Dockerfile ;;
esac

echo "Dockerfile generated successfully."
