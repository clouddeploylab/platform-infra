pipeline {
    agent { label 'built-in || master' }

    options {
        timeout(time: 30, unit: 'MINUTES')
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '80'))
    }

    parameters {
        string(name: 'SCAN_ID', defaultValue: '', description: 'Backend image_scan_jobs id')
        choice(name: 'SCAN_MODE', choices: ['IMAGE', 'GIT_BUILD'], description: 'IMAGE scans an existing image. GIT_BUILD clones, builds, then scans.')
        string(name: 'IMAGE_REF', defaultValue: '', description: 'Image reference for IMAGE mode, for example gohabor.anajak-khmer.site/project/app:tag or nginx:latest')

        string(name: 'REPO_URL', defaultValue: '', description: 'Git repository URL for GIT_BUILD mode')
        string(name: 'BRANCH', defaultValue: 'main', description: 'Git branch/tag for GIT_BUILD mode')
        string(name: 'REPO_CREDENTIALS_ID', defaultValue: '', description: 'Optional Jenkins credential id for private Git repositories')
        string(name: 'GIT_USERNAME', defaultValue: '', description: 'Optional Git username when no Jenkins credential id is used')
        password(name: 'GIT_PASSWORD', defaultValue: '', description: 'Optional Git password/token when no Jenkins credential id is used')
        string(name: 'DOCKERFILE_PATH', defaultValue: 'Dockerfile', description: 'Dockerfile path inside the repository')
        string(name: 'BUILD_CONTEXT', defaultValue: '.', description: 'Docker build context inside the repository')
        string(name: 'TARGET_IMAGE_NAME', defaultValue: '', description: 'Optional temp image name for GIT_BUILD mode')
        string(name: 'IMAGE_TAG', defaultValue: '', description: 'Optional temp image tag for GIT_BUILD mode')

        booleanParam(name: 'PRIVATE_REGISTRY', defaultValue: false, description: 'Login before scanning/pulling/pushing')
        string(name: 'REGISTRY_CREDENTIALS_ID', defaultValue: 'registry-credentials', description: 'Jenkins username/password credential id for private registry')
        string(name: 'REGISTRY_USERNAME', defaultValue: '', description: 'Optional registry username when no Jenkins credential id is used')
        password(name: 'REGISTRY_PASSWORD', defaultValue: '', description: 'Optional registry password/token when no Jenkins credential id is used')
        booleanParam(name: 'PUSH_TEMP_IMAGE', defaultValue: false, description: 'Push GIT_BUILD temp image to registry before scan')
        string(name: 'REGISTRY_REPOSITORY', defaultValue: 'goharbor-itp.anajak-khmer.site/scan-temp', description: 'Registry/project for temp images')

        string(name: 'TRIVY_SEVERITY', defaultValue: 'UNKNOWN,LOW,MEDIUM,HIGH,CRITICAL', description: 'Trivy severities to include')
        string(name: 'TRIVY_EXIT_CODE', defaultValue: '0', description: '0 reports only, 1 fails build when vulnerabilities match severity')
        string(name: 'TRIVY_SERVER_URL', defaultValue: '', description: 'Optional Trivy server URL, for example http://trivy-server:4954')
        string(name: 'TRIVY_BIN', defaultValue: 'trivy', description: 'Trivy executable name or absolute path on the Jenkins agent')

        string(name: 'BACKEND_CALLBACK_URL', defaultValue: '', description: 'Optional callback URL, for example https://api.example.com/api/v1/image-scanner/scans/{SCAN_ID}/callback')
        password(name: 'BACKEND_CALLBACK_TOKEN', defaultValue: '', description: 'Optional bearer token for backend callback')
        string(name: 'BACKEND_CALLBACK_CREDENTIALS_ID', defaultValue: 'a8s-jenkins-callback-token', description: 'Optional secret text credential id used as Bearer token for callback')
        booleanParam(name: 'UPLOAD_DEFECTDOJO', defaultValue: false, description: 'Upload report to DefectDojo if curl credentials are configured')
        string(name: 'DEFECTDOJO_URL', defaultValue: 'https://defetchdojo.anajak-khmer.site', description: 'DefectDojo base URL')
        string(name: 'DEFECTDOJO_CREDENTIALS_ID', defaultValue: 'DEFECTDOJO', description: 'DefectDojo API token credential id')
        string(name: 'DEFECTDOJO_PRODUCT_NAME', defaultValue: '', description: 'DefectDojo product name')
    }

    environment {
        REPORT_DIR = "trivy-reports"
        TRIVY_REPORT_JSON = "trivy-reports/trivy-report.json"
        TRIVY_REPORT_TABLE = "trivy-reports/trivy-report.txt"
    }

    stages {
        stage('Validate input') {
            steps {
                script {
                    env.NORMALIZED_SCAN_MODE = params.SCAN_MODE?.trim()?.toUpperCase()
                    if (!['IMAGE', 'GIT_BUILD'].contains(env.NORMALIZED_SCAN_MODE)) {
                        error('SCAN_MODE must be IMAGE or GIT_BUILD')
                    }

                    if (env.NORMALIZED_SCAN_MODE == 'IMAGE' && !params.IMAGE_REF?.trim()) {
                        error('IMAGE_REF is required for IMAGE mode')
                    }

                    if (env.NORMALIZED_SCAN_MODE == 'GIT_BUILD' && !params.REPO_URL?.trim()) {
                        error('REPO_URL is required for GIT_BUILD mode')
                    }

                    if (!(params.TRIVY_EXIT_CODE ==~ /^[0-9]+$/)) {
                        error('TRIVY_EXIT_CODE must be numeric, normally 0 or 1')
                    }

                    if (params.BACKEND_CALLBACK_URL?.trim()?.contains('localhost')) {
                        echo "[callback] WARNING: BACKEND_CALLBACK_URL points to localhost. Jenkins will call itself, not your backend."
                    }

                    sh 'mkdir -p "$REPORT_DIR"'
                    echo "SCAN_MODE=${env.NORMALIZED_SCAN_MODE}"
                }
            }
        }

        stage('Resolve target image') {
            steps {
                script {
                    if (env.NORMALIZED_SCAN_MODE == 'IMAGE') {
                        env.SCAN_IMAGE_REF = params.IMAGE_REF.trim()
                        echo "Scanning existing image: ${env.SCAN_IMAGE_REF}"
                    } else {
                        env.NORMALIZED_REPO_URL = params.REPO_URL.trim()
                        if (env.NORMALIZED_REPO_URL.contains('%')) {
                            try {
                                env.NORMALIZED_REPO_URL = java.net.URLDecoder.decode(env.NORMALIZED_REPO_URL, 'UTF-8')
                            } catch (Exception ignored) {
                                echo 'Could not decode REPO_URL, using original value.'
                            }
                        }

                        String repository = params.REGISTRY_REPOSITORY?.trim()
                        if (!repository) {
                            repository = 'local-scan'
                        }
                        repository = repository.replaceFirst(/^https?:\/\//, '').replaceAll(/\/+$/, '')

                        String repoName = params.TARGET_IMAGE_NAME?.trim()
                        if (!repoName) {
                            repoName = env.NORMALIZED_REPO_URL.tokenize('/').last().replaceFirst(/\.git$/, '')
                        }
                        repoName = repoName.toLowerCase().replaceAll(/[^a-z0-9._-]+/, '-').replaceAll(/^-+|-+$/, '')

                        String tag = params.IMAGE_TAG?.trim()
                        if (!tag) {
                            tag = "scan-${env.BUILD_NUMBER}"
                        }
                        tag = tag.replaceAll(/[^A-Za-z0-9_.-]+/, '-').replaceAll(/^-+|-+$/, '')

                        env.SCAN_IMAGE_REF = "${repository}/${repoName}:${tag}"
                        env.SCAN_REPOSITORY_HOST = repository.tokenize('/').first()
                        echo "Build image target: ${env.SCAN_IMAGE_REF}"
                    }
                }
            }
        }

        stage('Registry login') {
            when {
                expression { return params.PRIVATE_REGISTRY || params.PUSH_TEMP_IMAGE }
            }
            steps {
                script {
                    if (params.REGISTRY_CREDENTIALS_ID?.trim()) {
                        withCredentials([usernamePassword(
                            credentialsId: params.REGISTRY_CREDENTIALS_ID,
                            usernameVariable: 'RESOLVED_REGISTRY_USERNAME',
                            passwordVariable: 'RESOLVED_REGISTRY_PASSWORD'
                        )]) {
                            sh '''
                                set -eu
                                REGISTRY_HOST="${SCAN_REPOSITORY_HOST:-$(echo "$SCAN_IMAGE_REF" | cut -d/ -f1)}"
                                echo "[registry] logging into ${REGISTRY_HOST}"
                                echo "$RESOLVED_REGISTRY_PASSWORD" | docker login "$REGISTRY_HOST" \
                                    -u "$RESOLVED_REGISTRY_USERNAME" --password-stdin
                            '''
                        }
                    } else {
                        sh '''
                            set -eu
                            if [ -z "${REGISTRY_USERNAME:-}" ] || [ -z "${REGISTRY_PASSWORD:-}" ]; then
                                echo "Registry credentials are required for private registry login."
                                exit 1
                            fi
                            REGISTRY_HOST="${SCAN_REPOSITORY_HOST:-$(echo "$SCAN_IMAGE_REF" | cut -d/ -f1)}"
                            echo "[registry] logging into ${REGISTRY_HOST}"
                            echo "$REGISTRY_PASSWORD" | docker login "$REGISTRY_HOST" \
                                -u "$REGISTRY_USERNAME" --password-stdin
                        '''
                    }
                }
            }
        }

        stage('Checkout repository') {
            when {
                expression { return env.NORMALIZED_SCAN_MODE == 'GIT_BUILD' }
            }
            steps {
                dir('user-app') {
                    script {
                        deleteDir()
	                        if (params.REPO_CREDENTIALS_ID?.trim()) {
	                            checkout([
	                                $class: 'GitSCM',
	                                branches: [[name: "*/${params.BRANCH}"]],
	                                userRemoteConfigs: [[
	                                    url: env.NORMALIZED_REPO_URL,
	                                    credentialsId: params.REPO_CREDENTIALS_ID
	                                ]]
	                            ])
	                        } else if (params.GIT_USERNAME?.trim() && params.GIT_PASSWORD?.trim()) {
	                            sh '''
	                                set -eu
	                                cat > ../git-askpass.sh <<'EOF'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\\n' "$A8S_GIT_USERNAME" ;;
  *Password*) printf '%s\\n' "$A8S_GIT_PASSWORD" ;;
  *) printf '\\n' ;;
esac
EOF
	                                chmod 700 ../git-askpass.sh
	                                GIT_ASKPASS="$PWD/../git-askpass.sh" \
	                                GIT_TERMINAL_PROMPT=0 \
	                                A8S_GIT_USERNAME="$GIT_USERNAME" \
	                                A8S_GIT_PASSWORD="$GIT_PASSWORD" \
	                                git clone --depth 1 --branch "$BRANCH" "$NORMALIZED_REPO_URL" .
	                                rm -f ../git-askpass.sh
	                            '''
	                        } else {
	                            git url: env.NORMALIZED_REPO_URL, branch: params.BRANCH
	                        }
                        env.APP_COMMIT_SHA = sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
                        echo "Checked out commit ${env.APP_COMMIT_SHA}"
                    }
                }
            }
        }

        stage('Build temp image') {
            when {
                expression { return env.NORMALIZED_SCAN_MODE == 'GIT_BUILD' }
            }
            steps {
                dir('user-app') {
                    sh '''
                        set -eu
                        if [ ! -f "$DOCKERFILE_PATH" ]; then
                            echo "Dockerfile not found: $DOCKERFILE_PATH"
                            exit 1
                        fi
                        if [ ! -d "$BUILD_CONTEXT" ]; then
                            echo "Build context not found: $BUILD_CONTEXT"
                            exit 1
                        fi

                        echo "[build] docker build -f ${DOCKERFILE_PATH} -t ${SCAN_IMAGE_REF} ${BUILD_CONTEXT}"
                        docker build --pull --progress=plain --provenance=false \
                            -f "$DOCKERFILE_PATH" \
                            -t "$SCAN_IMAGE_REF" \
                            "$BUILD_CONTEXT"
                    '''
                }
            }
        }

        stage('Push temp image') {
            when {
                expression { return env.NORMALIZED_SCAN_MODE == 'GIT_BUILD' && params.PUSH_TEMP_IMAGE }
            }
            steps {
                sh '''
                    set -eu
                    echo "[push] pushing temp image ${SCAN_IMAGE_REF}"
                    docker push "$SCAN_IMAGE_REF"
                '''
            }
        }

        stage('Trivy scan') {
            steps {
                sh '''
                    set -eu
                    TRIVY_SEVERITY_VALUE="${TRIVY_SEVERITY:-CRITICAL,HIGH,MEDIUM,LOW}"
                    TRIVY_EXIT_CODE_VALUE="${TRIVY_EXIT_CODE:-0}"
                    TRIVY_SERVER_URL_VALUE="${TRIVY_SERVER_URL:-}"
                    RUN_TRIVY="${REPORT_DIR}/run-trivy"
                    TRIVY_CONFIGURED_BIN="${TRIVY_BIN:-trivy}"

                    if command -v "$TRIVY_CONFIGURED_BIN" >/dev/null 2>&1; then
                        cat > "$RUN_TRIVY" <<'EOF'
#!/bin/sh
set -eu
TRIVY_CMD="${TRIVY_BIN:-trivy}"
exec "$(command -v "$TRIVY_CMD")" "$@"
EOF
                    elif [ -x "$TRIVY_CONFIGURED_BIN" ]; then
                        cat > "$RUN_TRIVY" <<'EOF'
#!/bin/sh
set -eu
exec "${TRIVY_BIN}" "$@"
EOF
                    elif [ -x /usr/local/bin/trivy ]; then
                        cat > "$RUN_TRIVY" <<'EOF'
#!/bin/sh
set -eu
exec /usr/local/bin/trivy "$@"
EOF
                    elif [ -x /usr/bin/trivy ]; then
                        cat > "$RUN_TRIVY" <<'EOF'
#!/bin/sh
set -eu
exec /usr/bin/trivy "$@"
EOF
                    elif [ -x /snap/bin/trivy ]; then
                        cat > "$RUN_TRIVY" <<'EOF'
#!/bin/sh
set -eu
exec /snap/bin/trivy "$@"
EOF
                    elif [ -x /home/istad/bin/trivy ]; then
                        cat > "$RUN_TRIVY" <<'EOF'
#!/bin/sh
set -eu
exec /home/istad/bin/trivy "$@"
EOF
                    elif [ -x /home/istad/.local/bin/trivy ]; then
                        cat > "$RUN_TRIVY" <<'EOF'
#!/bin/sh
set -eu
exec /home/istad/.local/bin/trivy "$@"
EOF
                    elif command -v docker >/dev/null 2>&1; then
                        echo "[scan] Host Trivy not found; using Docker image aquasec/trivy:latest."
                        cat > "$RUN_TRIVY" <<'EOF'
#!/bin/sh
set -eu
CACHE_DIR="${HOME:-/tmp}/.cache/trivy"
mkdir -p "$CACHE_DIR"
exec docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD:/work" \
  -v "$CACHE_DIR:/root/.cache/trivy" \
  -w /work \
  aquasec/trivy:latest "$@"
EOF
                    else
                        echo "ERROR: Trivy was not found on this Jenkins agent and Docker fallback is unavailable."
                        echo "Agent: ${NODE_NAME:-unknown}"
                        echo "PATH: ${PATH:-}"
                        echo "Install Trivy on the istad agent, set TRIVY_BIN, or allow Docker to run aquasec/trivy:latest."
                        exit 127
                    fi
                    chmod +x "$RUN_TRIVY"
                    "$RUN_TRIVY" --version

                    TRIVY_ARGS="image --format json --output ${TRIVY_REPORT_JSON} --severity ${TRIVY_SEVERITY_VALUE} --exit-code ${TRIVY_EXIT_CODE_VALUE}"

                    if [ -n "${TRIVY_SERVER_URL_VALUE}" ]; then
                        TRIVY_ARGS="$TRIVY_ARGS --server ${TRIVY_SERVER_URL_VALUE}"
                    fi

                    echo "[scan] trivy ${TRIVY_ARGS} ${SCAN_IMAGE_REF}"
                    "$RUN_TRIVY" ${TRIVY_ARGS} "$SCAN_IMAGE_REF"

                    echo "[scan] writing table report"
                    TABLE_ARGS="image --format table --output ${TRIVY_REPORT_TABLE} --severity ${TRIVY_SEVERITY_VALUE} --exit-code 0"
                    if [ -n "${TRIVY_SERVER_URL_VALUE}" ]; then
                        TABLE_ARGS="$TABLE_ARGS --server ${TRIVY_SERVER_URL_VALUE}"
                    fi
                    "$RUN_TRIVY" ${TABLE_ARGS} "$SCAN_IMAGE_REF" || true
                '''
            }
            post {
                always {
                    archiveArtifacts artifacts: 'trivy-reports/*', fingerprint: true, allowEmptyArchive: true
                }
            }
        }

        stage('Upload DefectDojo') {
            when {
                expression { return params.UPLOAD_DEFECTDOJO }
            }
            steps {
                withCredentials([string(credentialsId: params.DEFECTDOJO_CREDENTIALS_ID, variable: 'DEFECTDOJO_TOKEN')]) {
                    sh '''
                        set -eu
                        PRODUCT_NAME="${DEFECTDOJO_PRODUCT_NAME:-${TARGET_IMAGE_NAME:-image-scan}}"
                        echo "[defectdojo] uploading Trivy report for ${PRODUCT_NAME}"
                        curl -sS -X POST "${DEFECTDOJO_URL%/}/api/v2/import-scan/" \
                            -H "Authorization: Token ${DEFECTDOJO_TOKEN}" \
                            -F "scan_type=Trivy Scan" \
                            -F "minimum_severity=Info" \
                            -F "active=true" \
                            -F "verified=false" \
                            -F "auto_create_context=true" \
                            -F "close_old_findings=true" \
                            -F "product_name=${PRODUCT_NAME}" \
                            -F "engagement_name=Jenkins-${BUILD_NUMBER}" \
                            -F "test_title=Trivy Image Scan - ${SCAN_IMAGE_REF}" \
                            -F "file=@${TRIVY_REPORT_JSON};type=application/json"
                    '''
                }
            }
        }

        stage('Callback backend') {
            when {
                expression { return params.BACKEND_CALLBACK_URL?.trim() }
            }
            steps {
                script {
                    String callbackUrl = params.BACKEND_CALLBACK_URL.trim()
                    if (params.SCAN_ID?.trim()) {
                        callbackUrl = callbackUrl.replace('{SCAN_ID}', params.SCAN_ID.trim())
                    }
                    env.RESOLVED_CALLBACK_URL = callbackUrl
                }
                script {
                    if (params.BACKEND_CALLBACK_CREDENTIALS_ID?.trim()) {
                        withCredentials([string(credentialsId: params.BACKEND_CALLBACK_CREDENTIALS_ID, variable: 'BACKEND_CALLBACK_TOKEN')]) {
	                            sh '''
	                                set +e
	                                curl -fsS -X POST "$RESOLVED_CALLBACK_URL" \
	                                    -H "Authorization: Bearer ${BACKEND_CALLBACK_TOKEN}" \
                                    -F "scanId=${SCAN_ID}" \
                                    -F "status=COMPLETED" \
                                    -F "imageRef=${SCAN_IMAGE_REF}" \
                                    -F "commitSha=${APP_COMMIT_SHA:-}" \
                                    -F "callbackToken=${BACKEND_CALLBACK_TOKEN}" \
                                    -F "report=@${TRIVY_REPORT_JSON};type=application/json"
                                    CALLBACK_STATUS=$?
                                    if [ "$CALLBACK_STATUS" -ne 0 ]; then
                                        echo "[callback] Backend callback failed with exit ${CALLBACK_STATUS}; Trivy report remains archived in Jenkins."
                                    fi
                                    exit 0
                            '''
                        }
                    } else {
	                        sh '''
	                            set +e
	                            curl -fsS -X POST "$RESOLVED_CALLBACK_URL" \
                                    -H "Authorization: Bearer ${BACKEND_CALLBACK_TOKEN:-}" \
	                                -F "scanId=${SCAN_ID}" \
	                                -F "status=COMPLETED" \
	                                -F "imageRef=${SCAN_IMAGE_REF}" \
                                -F "commitSha=${APP_COMMIT_SHA:-}" \
                                -F "callbackToken=${BACKEND_CALLBACK_TOKEN:-}" \
                                -F "report=@${TRIVY_REPORT_JSON};type=application/json"
                                CALLBACK_STATUS=$?
                                if [ "$CALLBACK_STATUS" -ne 0 ]; then
                                    echo "[callback] Backend callback failed with exit ${CALLBACK_STATUS}; Trivy report remains archived in Jenkins."
                                fi
                                exit 0
                        '''
                    }
                }
            }
        }
    }

    post {
        success {
            echo "Image scan completed: ${env.SCAN_IMAGE_REF}"
        }
        failure {
            script {
                if (params.BACKEND_CALLBACK_URL?.trim()) {
                    String callbackUrl = params.BACKEND_CALLBACK_URL.trim()
                    if (params.SCAN_ID?.trim()) {
                        callbackUrl = callbackUrl.replace('{SCAN_ID}', params.SCAN_ID.trim())
                    }
                    env.RESOLVED_CALLBACK_URL = callbackUrl
                    if (params.BACKEND_CALLBACK_CREDENTIALS_ID?.trim()) {
                        withCredentials([string(credentialsId: params.BACKEND_CALLBACK_CREDENTIALS_ID, variable: 'BACKEND_CALLBACK_TOKEN')]) {
                            sh '''
                                set +e
                                curl -fsS -X POST "$RESOLVED_CALLBACK_URL" \
                                    -H "Authorization: Bearer ${BACKEND_CALLBACK_TOKEN}" \
                                    -F "scanId=${SCAN_ID}" \
                                    -F "status=FAILED" \
                                    -F "imageRef=${SCAN_IMAGE_REF:-}" \
                                    -F "message=Jenkins image scan failed. Check build ${BUILD_URL}" \
                                    -F "callbackToken=${BACKEND_CALLBACK_TOKEN}" || true
                            '''
                        }
                    } else {
                        sh '''
                            set +e
                            curl -fsS -X POST "$RESOLVED_CALLBACK_URL" \
                                -H "Authorization: Bearer ${BACKEND_CALLBACK_TOKEN:-}" \
                                -F "scanId=${SCAN_ID}" \
                                -F "status=FAILED" \
                                -F "imageRef=${SCAN_IMAGE_REF:-}" \
                                -F "message=Jenkins image scan failed. Check build ${BUILD_URL}" \
                                -F "callbackToken=${BACKEND_CALLBACK_TOKEN:-}" || true
                        '''
                    }
                }
            }
            echo "Image scan failed."
        }
        always {
            sh '''
                set +e
                docker logout "$(echo "${SCAN_IMAGE_REF:-}" | cut -d/ -f1)" >/dev/null 2>&1
                if [ "${SCAN_MODE}" = "GIT_BUILD" ] && [ "${PUSH_TEMP_IMAGE}" != "true" ] && [ -n "${SCAN_IMAGE_REF:-}" ]; then
                    docker image rm "$SCAN_IMAGE_REF" >/dev/null 2>&1
                fi
            '''
            cleanWs()
        }
    }
}
