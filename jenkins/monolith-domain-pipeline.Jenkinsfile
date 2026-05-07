pipeline {
    agent { label 'built-in || master' }

    options {
        timeout(time: 10, unit: 'MINUTES')
        timestamps()
        buildDiscarder(logRotator(numToKeepStr: '50'))
    }

    parameters {
        string(name: 'OPERATION', defaultValue: 'domain', description: 'Expected operation: domain')
        string(name: 'USER_ID', defaultValue: '', description: 'Tenant user id')
        string(name: 'WORKSPACE_ID', defaultValue: '', description: 'Workspace namespace, for example ns-username-1234abcd')
        string(name: 'PROJECT_NAME', defaultValue: '', description: 'Project slug')
        string(name: 'APP_NAME', defaultValue: '', description: 'Legacy alias for PROJECT_NAME')
        string(name: 'CUSTOM_DOMAIN', defaultValue: '', description: 'Optional custom host')
        string(name: 'PLATFORM_DOMAIN', defaultValue: 'apps.example.com', description: 'Wildcard platform domain')
        string(name: 'GITOPS_BRANCH', defaultValue: 'main', description: 'GitOps branch to update')
        booleanParam(name: 'DOMAIN_ONLY_UPDATE', defaultValue: true, description: 'Always true for this job')
    }

    environment {
        INFRA_REPO_URL = credentials('infra-repo-url')
        GITOPS_REPO_URL = credentials('gitops-repo-url')
    }

    stages {
        stage('Validate input') {
            steps {
                script {
                    String operation = params.OPERATION?.trim() ?: 'domain'
                    if (operation != 'domain') {
                        error("monolith-domain-pipeline only supports OPERATION=domain, got ${operation}")
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
                    env.SAFE_WORKSPACE_ID = sh(
                        script: '''echo "$EFFECTIVE_WORKSPACE_ID" | tr '[:upper:]' '[:lower:]' | sed -E "s/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g" | cut -c1-63''',
                        returnStdout: true
                    ).trim()
                    env.SAFE_PROJECT_NAME = sh(
                        script: '''echo "$EFFECTIVE_PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed -E "s/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g" | cut -c1-40''',
                        returnStdout: true
                    ).trim()
                    echo "OPERATION=domain | GITOPS_BRANCH=${params.GITOPS_BRANCH} | WORKSPACE_ID=${env.EFFECTIVE_WORKSPACE_ID}"
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

        stage('Update GitOps domain') {
            steps {
                withCredentials([sshUserPrivateKey(credentialsId: 'gitops-ssh', keyFileVariable: 'SSH_KEY')]) {
                    sh '''
                        SCRIPTS_DIR=""
                        for base in "$WORKSPACE/platform-infra" "$WORKSPACE/plateform-infra"; do
                            if [ -f "$base/jenkins/scripts/update-gitops.sh" ]; then
                                SCRIPTS_DIR="$base/jenkins/scripts"
                                break
                            fi
                        done
                        if [ -z "$SCRIPTS_DIR" ]; then
                            echo "ERROR: update-gitops.sh not found in expected infra directories."
                            ls -la "$WORKSPACE" || true
                            exit 1
                        fi

                        bash "${SCRIPTS_DIR}/update-gitops.sh" \
                            --domain-only \
                            --gitops-repo "${GITOPS_REPO_URL}" \
                            --gitops-branch "${GITOPS_BRANCH}" \
                            --ssh-key "${SSH_KEY}" \
                            --workspace-id "${EFFECTIVE_WORKSPACE_ID}" \
                            --user-id "${USER_ID}" \
                            --project-name "${EFFECTIVE_PROJECT_NAME}" \
                            --custom-domain "${CUSTOM_DOMAIN}" \
                            --platform-domain "${PLATFORM_DOMAIN}"
                    '''
                }
            }
        }
    }

    post {
        success {
            script {
                String customDomain = params.CUSTOM_DOMAIN?.trim()
                String expectedHost = customDomain ?: "${env.SAFE_PROJECT_NAME}-${env.SAFE_WORKSPACE_ID}.${params.PLATFORM_DOMAIN}"
                echo "Domain update completed for ${env.EFFECTIVE_PROJECT_NAME}."
                echo "Expected URL: https://${expectedHost}"
            }
        }
        failure {
            echo 'Domain update failed. Check stage logs for details.'
        }
        always {
            cleanWs()
        }
    }
}
