@Library(['share_lib@master', 'a8s-sonarqube@main']) _

def notifyBackendRelease(String outcome) {
    String callbackBaseUrl = params.BACKEND_CALLBACK_URL?.trim()
    String projectId = params.PROJECT_ID?.trim()
    String releaseId = params.RELEASE_ID?.trim()

    if (!callbackBaseUrl || !projectId || !releaseId) {
        echo 'Skipping backend release callback: PROJECT_ID, RELEASE_ID, or BACKEND_CALLBACK_URL is missing.'
        return
    }

    String endpoint = outcome == 'complete' ? 'complete' : 'failed'
    Integer buildNumber = null
    try {
        buildNumber = env.BUILD_NUMBER?.trim() ? env.BUILD_NUMBER.trim().toInteger() : null
    } catch (Exception ignored) {
        buildNumber = null
    }

    String framework = env.FRAMEWORK?.trim() ?: params.FRAMEWORK?.trim() ?: ''
    String callbackUrl = "${callbackBaseUrl.replaceAll('/+$', '')}/api/v1/projects/${projectId}/releases/${releaseId}/${endpoint}"
    String callbackFile = ".a8s-release-callback-${endpoint}.json"
    Map payload = [
        buildNumber: buildNumber,
        framework: framework,
        statusMessage: outcome == 'complete' ? 'Deployment completed successfully' : 'Jenkins pipeline failed'
    ]

    writeFile file: callbackFile, text: groovy.json.JsonOutput.toJson(payload)
    withEnv([
        "A8S_RELEASE_CALLBACK_URL=${callbackUrl}",
        "A8S_RELEASE_CALLBACK_FILE=${callbackFile}",
        "A8S_CALLBACK_TOKEN=${params.CALLBACK_TOKEN ?: ''}"
    ]) {
        int callbackStatus = sh(
            script: '''
                set +x
                if [ -n "$A8S_CALLBACK_TOKEN" ]; then
                    curl -fsS -X POST "$A8S_RELEASE_CALLBACK_URL" \
                        -H 'Content-Type: application/json' \
                        -H "X-A8S-Jenkins-Callback-Token: $A8S_CALLBACK_TOKEN" \
                        --data @"$A8S_RELEASE_CALLBACK_FILE"
                else
                    curl -fsS -X POST "$A8S_RELEASE_CALLBACK_URL" \
                        -H 'Content-Type: application/json' \
                        --data @"$A8S_RELEASE_CALLBACK_FILE"
                fi
            ''',
            returnStatus: true
        )
        if (callbackStatus != 0) {
            echo "Backend release callback failed with exit code ${callbackStatus}."
        } else {
            echo "Backend release callback sent: ${endpoint} framework=${framework ?: 'unknown'}."
        }
    }
}

pipeline {
    agent { label 'built-in || master' }

    options {
        timeout(time: 20, unit: 'MINUTES')
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '50'))
    }

    parameters {
        string(name: 'OPERATION', defaultValue: 'deploy', description: 'Expected operation: deploy')
        string(name: 'REPO_URL', defaultValue: '', description: 'Git repository URL from user (GitHub/GitLab)')
        string(name: 'BRANCH', defaultValue: 'main', description: 'Git branch, tag, or ref to build')
        string(name: 'USER_ID', defaultValue: '', description: 'Tenant user id')
        string(name: 'WORKSPACE_ID', defaultValue: '', description: 'Workspace namespace, for example ns-username-1234abcd')
        string(name: 'CUSTOM_DOMAIN', defaultValue: '', description: 'Optional custom host (example: app.example.com)')
        string(name: 'PROJECT_NAME', defaultValue: '', description: 'Project slug')
        string(name: 'APP_NAME', defaultValue: '', description: 'Legacy alias for PROJECT_NAME')
        string(name: 'APP_PORT', defaultValue: '3000', description: 'Container application port')
        string(name: 'FRAMEWORK', defaultValue: '', description: 'Optional framework fallback from A8S backend')
        string(name: 'IMAGE_TAG', defaultValue: '', description: 'Image tag supplied by A8S release tracking')
        string(name: 'PROJECT_ID', defaultValue: '', description: 'A8S project id for release callback')
        string(name: 'RELEASE_ID', defaultValue: '', description: 'A8S release id for release callback')
        string(name: 'BACKEND_CALLBACK_URL', defaultValue: '', description: 'A8S backend public base URL for release callback')
        string(name: 'CALLBACK_TOKEN', defaultValue: '', description: 'Optional A8S backend callback token')
        text(name: 'ENV_JSON', defaultValue: '[]', description: 'Optional JSON array of runtime env vars')
        string(name: 'PLATFORM_DOMAIN', defaultValue: 'apps.example.com', description: 'Wildcard platform domain')
        string(name: 'GITOPS_BRANCH', defaultValue: 'main', description: 'GitOps branch to update')
        string(name: 'REGISTRY_REPOSITORY', defaultValue: 'gohabor.anajak-khmer.site/deployment-pipeline', description: 'Harbor host/project for pushed images')
        string(name: 'REPO_CREDENTIALS_ID', defaultValue: '', description: 'Optional Jenkins credential id for private user repositories')
        string(name: 'SONARQUBE_SERVER_NAME', defaultValue: 'sonarqube', description: 'Jenkins SonarQube server configuration name')
        string(name: 'SONARQUBE_SCANNER_TOOL', defaultValue: '', description: 'Optional Jenkins SonarScanner tool name')
        booleanParam(name: 'ENABLE_SONARQUBE_SCAN', defaultValue: false, description: 'Run SonarQube source analysis')
        booleanParam(name: 'ENABLE_SONARQUBE_QUALITY_GATE', defaultValue: false, description: 'Wait for SonarQube quality gate before build')
        booleanParam(name: 'ENABLE_TRIVY_SCAN', defaultValue: false, description: 'Run local Trivy image scan')
        booleanParam(name: 'ENABLE_GITOPS_UPDATE', defaultValue: true, description: 'Update GitOps repository after push')
    }

    environment {
        INFRA_REPO_URL = credentials('infra-repo-url')
        GITOPS_REPO_URL = credentials('gitops-repo-url')
    }

    stages {
        stage('Validate input') {
            steps {
                script {
                    String operation = params.OPERATION?.trim() ?: 'deploy'
                    if (operation != 'deploy') {
                        error("monolith-deploy-pipeline only supports OPERATION=deploy, got ${operation}")
                    }
                    if (!params.REPO_URL?.trim()) {
                        error('REPO_URL is required')
                    }
                    if (!params.USER_ID?.trim()) {
                        error('USER_ID is required')
                    }
                    env.EFFECTIVE_WORKSPACE_ID = params.WORKSPACE_ID?.trim()
                    if (!env.EFFECTIVE_WORKSPACE_ID) {
                        error('WORKSPACE_ID is required and must be the workspace namespace, for example ns-username-1234abcd')
                    }
                    env.EFFECTIVE_PROJECT_NAME = params.PROJECT_NAME?.trim() ? params.PROJECT_NAME.trim() : params.APP_NAME?.trim()
                    if (!env.EFFECTIVE_PROJECT_NAME) {
                        error('PROJECT_NAME (or APP_NAME) is required')
                    }
                    if (!(params.APP_PORT ==~ /^\d+$/)) {
                        error('APP_PORT must be numeric')
                    }

                    env.SAFE_USER_ID = sh(
                        script: '''echo "$USER_ID" | tr '[:upper:]' '[:lower:]' | sed -E "s/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g" | cut -c1-30''',
                        returnStdout: true
                    ).trim()
                    env.SAFE_WORKSPACE_ID = sh(
                        script: '''echo "$EFFECTIVE_WORKSPACE_ID" | tr '[:upper:]' '[:lower:]' | sed -E "s/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g" | cut -c1-63''',
                        returnStdout: true
                    ).trim()
                    env.SAFE_PROJECT_NAME = sh(
                        script: '''echo "$EFFECTIVE_PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed -E "s/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g" | cut -c1-40''',
                        returnStdout: true
                    ).trim()

                    def normalizedRegistry = (params.REGISTRY_REPOSITORY?.trim() ?: 'gohabor.anajak-khmer.site/deployment-pipeline')
                        .replaceFirst(/^https?:\/\//, '')
                        .replaceAll(/\/+$/, '')
                    if (!normalizedRegistry.contains('/')) {
                        error('REGISTRY_REPOSITORY must include registry host and Harbor project (example: gohabor.anajak-khmer.site/deployment-pipeline)')
                    }
                    env.EFFECTIVE_REGISTRY_REPOSITORY = normalizedRegistry

                    echo "OPERATION=deploy | ENABLE_GITOPS_UPDATE=${params.ENABLE_GITOPS_UPDATE} | GITOPS_BRANCH=${params.GITOPS_BRANCH} | WORKSPACE_ID=${env.EFFECTIVE_WORKSPACE_ID}"
                }
            }
        }

        stage('Checkout infra') {
            steps {
                dir('platform-infra') {
                    checkout([
                        $class: 'GitSCM',
                        branches: [[name: '*/main']],
                        userRemoteConfigs: [[url: env.INFRA_REPO_URL]]
                    ])
                }
            }
        }

        stage('Checkout user repository') {
            steps {
                dir('user-app') {
                    script {
                        deleteDir()
                        env.NORMALIZED_REPO_URL = params.REPO_URL
                        if (params.REPO_URL?.contains('%')) {
                            try {
                                env.NORMALIZED_REPO_URL = java.net.URLDecoder.decode(params.REPO_URL, 'UTF-8')
                            } catch (Exception ignored) {
                                echo 'Could not decode REPO_URL, using original value.'
                            }
                        }

                        if (params.REPO_CREDENTIALS_ID?.trim()) {
                            checkout([
                                $class: 'GitSCM',
                                branches: [[name: "*/${params.BRANCH}"]],
                                userRemoteConfigs: [[
                                    url: env.NORMALIZED_REPO_URL,
                                    credentialsId: params.REPO_CREDENTIALS_ID
                                ]]
                            ])
                        } else {
                            git url: env.NORMALIZED_REPO_URL, branch: params.BRANCH
                        }

                        env.APP_COMMIT_SHA = sh(script: 'git rev-parse --short=12 HEAD', returnStdout: true).trim()
                        env.NORMALIZED_REGISTRY_REPOSITORY = env.EFFECTIVE_REGISTRY_REPOSITORY
                        env.IMAGE_TAG = params.IMAGE_TAG?.trim() ?: "${env.SAFE_USER_ID}-${env.BUILD_NUMBER}-${env.APP_COMMIT_SHA}"
                        env.IMAGE_REPOSITORY = "${env.NORMALIZED_REGISTRY_REPOSITORY}/${env.SAFE_USER_ID}/${env.SAFE_PROJECT_NAME}"
                        env.IMAGE_FULL = "${env.IMAGE_REPOSITORY}:${env.IMAGE_TAG}"
                        env.REGISTRY_LOGIN_SERVER = env.EFFECTIVE_REGISTRY_REPOSITORY.split('/')[0]

                        echo "Resolved image: ${env.IMAGE_FULL}"
                    }
                }
            }
        }

        stage('Detect framework') {
            steps {
                dir('user-app') {
                    script {
                        String scriptsDir = sh(
                            script: '''
                                set -e
                                for d in "$WORKSPACE/platform-infra/jenkins/scripts" "$WORKSPACE/plateform-infra/jenkins/scripts"; do
                                    if [ -f "$d/detect-framework.sh" ]; then
                                        echo "$d"
                                        exit 0
                                    fi
                                done
                                echo "ERROR: detect-framework.sh not found in expected infra directories." >&2
                                ls -la "$WORKSPACE" >&2 || true
                                exit 1
                            ''',
                            returnStdout: true
                        ).trim()
                        String detectedFramework = sh(
                            script: "bash '${scriptsDir}/detect-framework.sh'",
                            returnStdout: true
                        ).trim()
                        env.FRAMEWORK = detectedFramework ?: params.FRAMEWORK?.trim()
                        echo "Detected framework: ${env.FRAMEWORK}"
                    }
                }
            }
        }

        stage('SonarQube Analysis') {
            when {
                expression { return params.ENABLE_SONARQUBE_SCAN }
            }
            steps {
                dir('user-app') {
                    script {
                        a8sSonarScan(
                            server: params.SONARQUBE_SERVER_NAME?.trim() ?: 'sonarqube',
                            scannerTool: params.SONARQUBE_SCANNER_TOOL?.trim(),
                            projectKey: "${env.SAFE_WORKSPACE_ID}-${env.SAFE_PROJECT_NAME}",
                            projectName: env.EFFECTIVE_PROJECT_NAME,
                            projectVersion: env.APP_COMMIT_SHA,
                            sources: '.',
                            exclusions: '**/node_modules/**,**/.next/**,**/dist/**,**/build/**,**/target/**,**/vendor/**,**/.git/**'
                        )
                    }
                }
            }
        }

        stage('SonarQube Quality Gate') {
            when {
                expression { return params.ENABLE_SONARQUBE_SCAN && params.ENABLE_SONARQUBE_QUALITY_GATE }
            }
            steps {
                a8sSonarQualityGate(timeoutMinutes: 5, abortPipeline: true)
            }
        }

        stage('Prepare Dockerfile') {
            steps {
                dir('user-app') {
                    sh '''
                        SCRIPTS_DIR=""
                        for d in "$WORKSPACE/platform-infra/jenkins/scripts" "$WORKSPACE/plateform-infra/jenkins/scripts"; do
                            if [ -f "$d/generate-dockerfile.sh" ]; then
                                SCRIPTS_DIR="$d"
                                break
                            fi
                        done
                        if [ -z "$SCRIPTS_DIR" ]; then
                            echo "ERROR: generate-dockerfile.sh not found in expected infra directories."
                            ls -la "$WORKSPACE" || true
                            exit 1
                        fi

                        case "$FRAMEWORK" in
                          springboot-*)
                            echo "Using platform-managed Spring Boot Dockerfile template."
                            FORCE_PLATFORM_DOCKERFILE=true bash "${SCRIPTS_DIR}/generate-dockerfile.sh" "${FRAMEWORK}" "${SCRIPTS_DIR}"
                            ;;
                          *)
                            if [ -f Dockerfile ]; then
                                echo "Using user-provided Dockerfile."
                            else
                                echo "Generating Dockerfile from platform template."
                                bash "${SCRIPTS_DIR}/generate-dockerfile.sh" "${FRAMEWORK}" "${SCRIPTS_DIR}"
                            fi
                            ;;
                        esac
                    '''
                }
            }
        }

        stage('Build, Scan, Push') {
            agent { label 'istad' }
            steps {
                script {
                    dir('platform-infra') {
                        checkout([
                            $class: 'GitSCM',
                            branches: [[name: '*/main']],
                            userRemoteConfigs: [[url: env.INFRA_REPO_URL]]
                        ])
                    }

                    dir('user-app') {
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
                        } else {
                            git url: env.NORMALIZED_REPO_URL, branch: params.BRANCH
                        }

                        sh '''
                            SCRIPTS_DIR=""
                            for d in "$WORKSPACE/platform-infra/jenkins/scripts" "$WORKSPACE/plateform-infra/jenkins/scripts"; do
                                if [ -f "$d/generate-dockerfile.sh" ]; then
                                    SCRIPTS_DIR="$d"
                                    break
                                fi
                            done
                            if [ -z "$SCRIPTS_DIR" ]; then
                                echo "ERROR: generate-dockerfile.sh not found in expected infra directories."
                                ls -la "$WORKSPACE" || true
                                exit 1
                            fi

                            case "$FRAMEWORK" in
                              springboot-*)
                                FORCE_PLATFORM_DOCKERFILE=true bash "${SCRIPTS_DIR}/generate-dockerfile.sh" "${FRAMEWORK}" "${SCRIPTS_DIR}"
                                ;;
                              *)
                                if [ ! -f Dockerfile ]; then
                                    bash "${SCRIPTS_DIR}/generate-dockerfile.sh" "${FRAMEWORK}" "${SCRIPTS_DIR}"
                                fi
                                ;;
                            esac

                            echo "[build] Starting docker build for ${IMAGE_FULL}"
                            docker build --pull --progress=plain --provenance=false -t "$IMAGE_FULL" .
                            echo "[build] Docker build completed"
                        '''
                    }

                    if (params.ENABLE_TRIVY_SCAN) {
                        echo "[scan] Starting Trivy scan for ${env.IMAGE_FULL}"
                        sh '''
                            set -eu
                            mkdir -p trivy-reports
                            trivy --version
                            trivy image \
                                --format json \
                                --output trivy-reports/trivy-report.json \
                                --severity HIGH,CRITICAL \
                                --exit-code 0 \
                                "$IMAGE_FULL"
                            trivy image \
                                --format table \
                                --output trivy-reports/trivy-report.txt \
                                --severity HIGH,CRITICAL \
                                --exit-code 0 \
                                "$IMAGE_FULL" || true
                        '''
                        archiveArtifacts artifacts: 'trivy-reports/*', fingerprint: true, allowEmptyArchive: true
                        uploadDefectDojo(
                            defectdojoUrl: 'https://defectdojo.devith.it.com',
                            defectdojoCredentialId: 'DEFECTDOJO',
                            reportPath: 'trivy-reports/trivy-report.json',
                            productTypeName: 'Web Applications',
                            productName: env.EFFECTIVE_PROJECT_NAME,
                            engagementName: "Jenkins-${env.BUILD_NUMBER}",
                            testTitle: "Trivy Image Scan - ${env.IMAGE_TAG}"
                        )
                        sh '''
                            set -eu
                            trivy image \
                                --format table \
                                --severity HIGH,CRITICAL \
                                --exit-code 1 \
                                "$IMAGE_FULL"
                        '''
                    }

                    withCredentials([usernamePassword(
                        credentialsId: 'registry-credentials',
                        usernameVariable: 'REGISTRY_USERNAME',
                        passwordVariable: 'REGISTRY_PASSWORD'
                    )]) {
                        sh '''
                            echo "[push] Pushing image ${IMAGE_FULL}"
                            echo "${REGISTRY_PASSWORD}" | docker login "${REGISTRY_LOGIN_SERVER}" \
                                -u "${REGISTRY_USERNAME}" --password-stdin
                            docker push "${IMAGE_FULL}"
                            echo "[push] Image push completed"
                        '''
                    }
                }
            }
        }

        stage('Update GitOps repository') {
            when {
                expression { return params.ENABLE_GITOPS_UPDATE }
            }
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'gitops-ssh', keyFileVariable: 'SSH_KEY')]) {
                    sh '''
                        SCRIPTS_DIR=""
                        INFRA_BASE_DIR=""
                        for base in "$WORKSPACE/platform-infra" "$WORKSPACE/plateform-infra"; do
                            if [ -f "$base/jenkins/scripts/update-gitops.sh" ]; then
                                SCRIPTS_DIR="$base/jenkins/scripts"
                                INFRA_BASE_DIR="$base"
                                break
                            fi
                        done
                        if [ -z "$SCRIPTS_DIR" ]; then
                            echo "ERROR: update-gitops.sh not found in expected infra directories."
                            ls -la "$WORKSPACE" || true
                            exit 1
                        fi

                        bash "${SCRIPTS_DIR}/update-gitops.sh" \
                            --operation deploy \
                            --gitops-repo "${GITOPS_REPO_URL}" \
                            --gitops-branch "${GITOPS_BRANCH}" \
                            --ssh-key "${SSH_KEY}" \
                            --workspace-id "${EFFECTIVE_WORKSPACE_ID}" \
                            --user-id "${USER_ID}" \
                            --project-name "${EFFECTIVE_PROJECT_NAME}" \
                            --custom-domain "${CUSTOM_DOMAIN}" \
                            --image-repository "${IMAGE_REPOSITORY}" \
                            --image-tag "${IMAGE_TAG}" \
                            --app-port "${APP_PORT}" \
                            --env-json "${ENV_JSON}" \
                            --platform-domain "${PLATFORM_DOMAIN}" \
                            --framework "${FRAMEWORK}" \
                            --commit-sha "${APP_COMMIT_SHA}" \
                            --build-number "${BUILD_NUMBER}" \
                            --chart-source "${INFRA_BASE_DIR}/helm/app-template"
                    '''
                }
            }
        }
    }

    post {
        success {
            script {
                echo "Deployment requested successfully for ${env.EFFECTIVE_PROJECT_NAME}."
                echo "Image: ${env.IMAGE_FULL}"
                String customDomain = params.CUSTOM_DOMAIN?.trim()
                String expectedHost = customDomain ?: "${env.SAFE_PROJECT_NAME}-${env.SAFE_WORKSPACE_ID}.${params.PLATFORM_DOMAIN}"
                echo "Expected URL: https://${expectedHost}"
                notifyBackendRelease('complete')
            }
        }
        failure {
            echo 'Deployment failed. Check stage logs for details.'
            script {
                notifyBackendRelease('failed')
            }
        }
        always {
            cleanWs()
        }
    }
}
