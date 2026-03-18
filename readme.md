# platform-infra

CI templates and scripts used by Jenkins to build user apps and update the GitOps repo.

## Pipeline responsibilities

- Detect project framework.
- Generate Dockerfile template (if user repo has no Dockerfile).
- Build and push container image.
- Write `deployment.yaml`, `service.yaml`, `ingress.yaml` to `platform-gitops`.

## Supported frameworks

- `nextjs`
- `nodejs`
- `springboot`
- `gradle`
- `go`
- `fastapi`
- `python`
- `static`

## Required Jenkins credentials

Create these credentials in Jenkins before running `deploy-pipeline`:

- `registry-url` (Secret text)
  - Value for self-hosted GitLab registry: `registry.gitlab.yourdomain.com/group/project`
- `registry-credentials` (Username with password)
  - Username: GitLab username (or deploy token username)
  - Password: GitLab personal access token / deploy token password
- `gitops-repo-url` (Secret text)
  - Example: `git@github.com:yourorg/platform-gitops.git`
- `gitops-ssh` (SSH Username with private key)
  - SSH key with push access to GitOps repo
- `infra-repo-url` (Secret text)
  - Example: `https://github.com/yourorg/platform-infra.git`
- `infra-repo-creds` (Username/password or token credential for `infra-repo-url`)

## Parameters you pass when triggering deploy-pipeline

- `REPO_URL`: user app git URL
- `BRANCH`: user app branch
- `APP_NAME`: unique app slug
- `APP_PORT`: app container port
- `PLATFORM_DOMAIN`: base domain (example: `tochratana.com`)

## GitLab registry example

If your registry server is `registry.gitlab.yourdomain.com` and images should live under
`group/project`, set:

- `registry-url` = `registry.gitlab.yourdomain.com/group/project`
- `registry-credentials` = GitLab user/token with push permission

The pipeline will:

- Login to `registry.gitlab.yourdomain.com`
- Push image as:
  - `registry.gitlab.yourdomain.com/group/project/<app-name>:<build-number>`
