#!/bin/bash
set -e

# Outputs exactly one word to stdout — Jenkinsfile captures it as FRAMEWORK
is_fastapi_project() {
    if [ -f "requirements.txt" ] && grep -Eiq '(^|[[:space:]])fastapi([<>=~!].*)?$' requirements.txt; then
        return 0
    fi

    if [ -f "pyproject.toml" ] && grep -Eiq '(^|[[:space:]])fastapi([[:space:]]|$)' pyproject.toml; then
        return 0
    fi

    return 1
}

if [ -f "package.json" ]; then
    if node -e "process.exit(require('./package.json').dependencies?.next ? 0 : 1)" 2>/dev/null; then
        echo "nextjs"
    else
        echo "nodejs"
    fi
elif [ -f "pom.xml" ]; then
    echo "springboot"
elif [ -f "build.gradle" ] || [ -f "build.gradle.kts" ]; then
    echo "gradle"
elif [ -f "go.mod" ]; then
    echo "go"
elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ]; then
    if is_fastapi_project; then
        echo "fastapi"
    else
        echo "python"
    fi
elif [ -f "index.html" ] || [ -f "public/index.html" ]; then
    echo "static"
else
    echo "static"
fi
