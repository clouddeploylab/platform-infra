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

    String framework = params.FRAMEWORK?.trim() ?: ''
    String callbackToken = env.A8S_JENKINS_CALLBACK_TOKEN?.trim() ?: params.CALLBACK_TOKEN?.trim() ?: ''
    String callbackUrl = "${callbackBaseUrl.replaceAll('/+$', '')}/api/v1/projects/${projectId}/releases/${releaseId}/${endpoint}"
    String callbackFile = ".a8s-release-callback-${endpoint}.json"
    Map payload = [
        buildNumber: buildNumber,
        framework: framework,
        statusMessage: outcome == 'complete' ? 'Rollback completed successfully' : 'Rollback failed'
    ]

    writeFile file: callbackFile, text: groovy.json.JsonOutput.toJson(payload)
    withEnv([
        "A8S_RELEASE_CALLBACK_URL=${callbackUrl}",
        "A8S_RELEASE_CALLBACK_FILE=${callbackFile}",
        "A8S_CALLBACK_TOKEN=${callbackToken}"
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
            echo "Backend rollback callback failed with exit code ${callbackStatus}."
        } else {
            echo "Backend rollback callback sent: ${endpoint} framework=${framework ?: 'unknown'}."
        }
    }
}

pipeline {
    agent { label 'built-in || master' }

    options {
        timeout(time: 10, unit: 'MINUTES')
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '50'))
    }

    parameters {
        string(name: 'OPERATION', defaultValue: 'rollback', description: 'Expected operation: rollback')
        string(name: 'REPO_URL', defaultValue: '', description: 'Accepted for backend compatibility, not used by rollback')
        string(name: 'BRANCH', defaultValue: 'main', description: 'Accepted for backend compatibility, not used by rollback')
        string(name: 'USER_ID', defaultValue: '', description: 'Tenant user id')
        string(name: 'WORKSPACE_ID', defaultValue: '', description: 'Workspace namespace, for example ns-username-1234abcd')
        string(name: 'CUSTOM_DOMAIN', defaultValue: '', description: 'Optional custom host')
        string(name: 'PROJECT_NAME', defaultValue: '', description: 'Project slug')
        string(name: 'APP_NAME', defaultValue: '', description: 'Legacy alias for PROJECT_NAME')
        string(name: 'APP_PORT', defaultValue: '3000', description: 'Container application port from selected release')
        string(name: 'FRAMEWORK', defaultValue: '', description: 'Framework saved on selected release')
        string(name: 'IMAGE_TAG', defaultValue: '', description: 'Existing image tag from selected release')
        string(name: 'PROJECT_ID', defaultValue: '', description: 'A8S project id for release callback')
        string(name: 'RELEASE_ID', defaultValue: '', description: 'A8S rollback release id for release callback')
        string(name: 'BACKEND_CALLBACK_URL', defaultValue: '', description: 'A8S backend public base URL for release callback')
        string(name: 'CALLBACK_TOKEN', defaultValue: '', description: 'Legacy fallback only. Jenkins normally uses credential a8s-jenkins-callback-token.')
        text(name: 'ENV_JSON', defaultValue: '[]', description: 'Runtime env vars saved on selected release')
        string(name: 'PLATFORM_DOMAIN', defaultValue: 'apps.example.com', description: 'Wildcard platform domain')
        string(name: 'GITOPS_BRANCH', defaultValue: 'main', description: 'GitOps branch to update')
        string(name: 'REGISTRY_REPOSITORY', defaultValue: 'goharbor-itp.anajak-khmer.site/deployment-pipeline', description: 'Harbor host/project that stores release images')
        booleanParam(name: 'ROLLBACK_MODE', defaultValue: true, description: 'Always true for this job')
        booleanParam(name: 'ENABLE_GITOPS_UPDATE', defaultValue: true, description: 'Update GitOps repository')
    }

    environment {
        INFRA_REPO_URL = credentials('infra-repo-url')
        GITOPS_REPO_URL = credentials('gitops-repo-url')
        A8S_JENKINS_CALLBACK_TOKEN = credentials('a8s-jenkins-callback-token')
    }

    stages {
        stage('Validate input') {
            steps {
                script {
                    String operation = params.OPERATION?.trim() ?: 'rollback'
                    if (operation != 'rollback') {
                        error("monolith-rollback-pipeline only supports OPERATION=rollback, got ${operation}")
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
                    if (!params.FRAMEWORK?.trim()) {
                        error('FRAMEWORK is required for rollback')
                    }
                    if (!params.IMAGE_TAG?.trim()) {
                        error('IMAGE_TAG is required for rollback')
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

                    env.NORMALIZED_REGISTRY_REPOSITORY = (params.REGISTRY_REPOSITORY?.trim() ?: 'goharbor-itp.anajak-khmer.site/deployment-pipeline')
                        .replaceFirst(/^https?:\/\//, '')
                        .replaceAll(/\/+$/, '')
                    if (!env.NORMALIZED_REGISTRY_REPOSITORY.contains('/')) {
                        error('REGISTRY_REPOSITORY must include registry host and Harbor project (example: goharbor-itp.anajak-khmer.site/deployment-pipeline)')
                    }

                    env.IMAGE_TAG = params.IMAGE_TAG.trim()
                    env.IMAGE_REPOSITORY = "${env.NORMALIZED_REGISTRY_REPOSITORY}/${env.SAFE_USER_ID}/${env.SAFE_PROJECT_NAME}"
                    env.IMAGE_FULL = "${env.IMAGE_REPOSITORY}:${env.IMAGE_TAG}"
                    env.APP_COMMIT_SHA = "rollback-${env.BUILD_NUMBER}"
                    env.FRAMEWORK = params.FRAMEWORK.trim()

                    echo "OPERATION=rollback | IMAGE=${env.IMAGE_FULL} | GITOPS_BRANCH=${params.GITOPS_BRANCH}"
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

        stage('Update GitOps rollback') {
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
                            --operation rollback \
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
                echo "Rollback requested successfully for ${env.EFFECTIVE_PROJECT_NAME}."
                echo "Image: ${env.IMAGE_FULL}"
                notifyBackendRelease('complete')
            }
        }
        failure {
            echo 'Rollback failed. Check stage logs for details.'
            script {
                notifyBackendRelease('failed')
            }
        }
        always {
            cleanWs()
        }
    }
}
