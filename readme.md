# platform-infra

Production-grade CI/CD building blocks for a multi-tenant deployment platform (Vercel/Render style).

## What this repo provides

- Single generic Jenkins pipeline for all frameworks
- Automatic framework detection and Dockerfile fallback templates
- Spring Boot Docker templates auto-detect the Java version from the app build files
- App container ports are framework-aware:
  - `nextjs` / `nodejs` -> `3000`
  - `react` / `laravel` / `php` / `static` / `tailwind-static` -> `80`
  - `springboot-*` / `java-*` -> `8080`
  - `fastapi` / `flask` / `python` -> `8000`
  - `APP_PORT` still works as an explicit override when you need a custom port
- App health checks are framework-aware too:
  - Spring Boot and Java apps use TCP startup/readiness/liveness probes
  - Web and API apps keep HTTP probes on `/`
- Docker image build/push with immutable version tag format:
  - `<userId>-<buildNumber>-<commitSHA>`
- GitOps update script that writes to:
  - `apps/<userId>/<projectName>/`
  - runtime env vars are passed as `ENV_JSON` and written into the generated Helm values
- Helm templates for Deployment, Service, Ingress, and HPA
- Platform-managed Java Docker templates:
  - `Dockerfile.gradle`
  - `Dockerfile.maven`
- Conflict-safe GitOps pushes with retry logic

## Supported frameworks

- Node.js (`nextjs`, `react`, `nodejs`)
- Static Tailwind/Vite HTML (`tailwind-static`)
- Java (`springboot-maven`, `springboot-gradle`, `java-maven`, `java-gradle`)
- Python (`fastapi`, `flask`, `python`)
- PHP (`laravel`, `php`)
- Static sites (`static`)

## Static Tailwind/HTML projects

Projects like `https://github.com/tochratana/Tailwind.git` are detected as `tailwind-static` when they have `package.json`, an HTML entrypoint, and Tailwind/Vite config or dependencies. The generated Dockerfile runs `npm ci` when a lockfile exists, falls back to `npm install` when it does not, runs `npm run build` when present, compiles `src/input.css` when no build script exists, then serves `dist/`, `build/`, `public/`, `src/`, or the root `index.html` with Nginx on port `80`.

## Key files

- `jenkins/Jenkinsfile`
- `jenkins/image-scan-pipeline.Jenkinsfile`
- `jenkins/scripts/detect-framework.sh`
- `jenkins/scripts/generate-dockerfile.sh`
- `jenkins/scripts/update-gitops.sh`
- `docker/dockerfiles/*`
- `helm/app-template/*`

## Jenkins credentials required

- `infra-repo-url` (Secret text)
- `infra-repo-creds` (Git credentials)
- `REGISTRY_REPOSITORY` pipeline parameter (default `goharbor-itp.anajak-khmer.site/deployment-pipeline`)
- `registry-credentials` (Username/Password)
- `gitops-repo-url` (Secret text, SSH URL or GitHub HTTPS URL)
- `gitops-ssh` (SSH private key with write access to the GitOps repository)
- Optional for image scanning: `DEFECTDOJO` (Secret text API token)
- Optional for image scanning callbacks: backend callback token as Secret text

## Pipeline inputs

- `REPO_URL`
- `BRANCH`
- `USER_ID`
- `PROJECT_NAME`
- `APP_PORT`
- `ENV_JSON` (optional JSON array of runtime env vars, manual form or `.env` import)
- `PLATFORM_DOMAIN`
  - default: `autonomous-istad.com`
- `GITOPS_BRANCH`
- `REPO_CREDENTIALS_ID` (optional)
- `DOMAIN_ONLY_UPDATE` (optional, boolean)
  - `true` means Jenkins skips checkout/build/push and only updates GitOps host/domain
  - Use this for custom-domain changes after the first successful full deployment

## Local validation

```bash
bash -n jenkins/scripts/detect-framework.sh
bash -n jenkins/scripts/generate-dockerfile.sh
bash -n jenkins/scripts/update-gitops.sh
```

## Image scan pipeline

Create a Jenkins Pipeline job named `image-scan-pipeline` and point it to
`jenkins/image-scan-pipeline.Jenkinsfile`.

Main modes:

- `SCAN_MODE=IMAGE`: scan an existing Harbor/Docker Hub/private registry image from `IMAGE_REF`.
- `SCAN_MODE=GIT_BUILD`: clone `REPO_URL`, build a temporary image, then scan it.

Common parameters:

- `SCAN_ID`: backend scan job id.
- `IMAGE_REF`: image ref for Harbor/external scans, for example `goharbor-itp.anajak-khmer.site/project/app:tag`.
- `REPO_URL`, `BRANCH`, `DOCKERFILE_PATH`, `BUILD_CONTEXT`: Git build scan inputs.
- `PRIVATE_REGISTRY=true` and `REGISTRY_CREDENTIALS_ID=registry-credentials` for private images.
- `BACKEND_CALLBACK_URL`: optional callback URL, for example `https://api.example.com/api/v1/image-scanner/scans/{SCAN_ID}/callback`.
- `BACKEND_CALLBACK_CREDENTIALS_ID`: optional Secret text credential used as callback bearer token.
- `TRIVY_SERVER_URL`: optional Trivy server URL. Leave empty to use local Trivy CLI on the Jenkins `trivy` agent.
