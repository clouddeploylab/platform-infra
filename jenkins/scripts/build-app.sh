#!/bin/bash
set -e

FRAMEWORK=$1

echo "Building application for framework: ${FRAMEWORK}"

case "$FRAMEWORK" in
    nextjs)
        npm ci
        npm run build
        ;;
    nodejs)
        npm ci --production
        ;;
    springboot)
        chmod +x ./mvnw 2>/dev/null || true
        ./mvnw package -DskipTests --batch-mode
        ;;
    gradle)
        chmod +x ./gradlew
        ./gradlew build -x test
        ;;
    go)
        go mod download
        go build -o app ./...
        ;;
    python)
        pip install -r requirements.txt --quiet 2>/dev/null || \
        pip install -r pyproject.toml --quiet 2>/dev/null || true
        ;;
    static)
        echo "Static site — no build step needed."
        ;;
esac

echo "Build complete."