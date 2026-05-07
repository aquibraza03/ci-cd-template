# Adservice and Emailservice Integration Guide

## Scope

This guide covers the second Online Boutique integration slice for this platform:

- `adservice`
- `emailservice`

No other Online Boutique services were integrated in this pass. `auth-service` remains ignored because it is demo-only and is disabled from service detection with `ci.enabled: false`.

## Demo Application Analysis

Online Boutique services are mostly gRPC services. This platform contract expects each integrated service to be independently deployable under `services/<service-name>/` with an HTTP runtime surface:

- `GET /`
- `GET /health`
- `GET /ready`

Selected services:

| Service | Upstream role | Original language | Platform port | Dependencies | Missing platform contract |
| --- | --- | --- | ---: | --- | --- |
| `adservice` | Returns contextual ads | Java | 9555 | In-memory ad catalog | HTTP `/`, `/health`, `/ready` |
| `emailservice` | Sends mock order emails | Python | 8080 | None for mock adapter | HTTP `/`, `/health`, `/ready` |

The platform integration uses HTTP adapters that preserve the demo role and source metadata while satisfying the platform contract. The original gRPC implementations are not copied directly because the platform deploy, probe, and runtime validation model is HTTP based.

## Service Adaptation

Created:

```text
services/adservice/
  Dockerfile
  Jenkinsfile
  service.yml
  src/AdServiceHttp.java
  src/AdServiceHttpTest.java

services/emailservice/
  Dockerfile
  Jenkinsfile
  service.yml
  src/server.py
  src/test_server.py
```

### adservice

Contract:

```yaml
name: adservice
language: java

docker:
  context: .
  port: 9555

deploy:
  type: k8s
  serviceType: NodePort
  servicePort: 80
  healthcheck: /health
  readiness: /ready
  probes:
    readiness:
      initialDelaySeconds: 20
      periodSeconds: 5
      timeoutSeconds: 2
    liveness:
      initialDelaySeconds: 30
      periodSeconds: 10
      timeoutSeconds: 2
```

Runtime endpoints:

- `/` returns service identity and ad catalog count.
- `/health` returns `{"status":"ok","service":"adservice"}`.
- `/ready` returns `{"status":"ready","adCount":7}`.
- `/ads?context=...` returns contextual mock ads.

### emailservice

Contract:

```yaml
name: emailservice
language: python

docker:
  context: .
  port: 8080

deploy:
  type: k8s
  serviceType: NodePort
  servicePort: 80
  healthcheck: /health
  readiness: /ready
  probes:
    readiness:
      initialDelaySeconds: 10
      periodSeconds: 5
      timeoutSeconds: 2
    liveness:
      initialDelaySeconds: 30
      periodSeconds: 10
      timeoutSeconds: 2
```

Runtime endpoints:

- `/` returns service identity and mock mode.
- `/health` returns `{"status":"ok","service":"emailservice"}`.
- `/ready` returns `{"status":"ready","mode":"mock"}`.
- `/send?to=...&order=...` returns an accepted mock send response.

## Platform Changes

The integration exposed several shared platform issues. These were fixed without hardcoding service-specific values in base templates.

### `ci/test.sh`

Added first-class Java and Python test handling:

- Java services compile `src/*.java` and run `*Test.java` classes.
- Python services use `pytest` when installed, otherwise standard-library `unittest` discovery.
- Python services without tests still get a syntax check through `compileall`.

### `ci/security.sh`

Trivy image scans hung on the local Windows Docker image backend when library package analysis was enabled. The security script now has configurable scan controls:

```bash
TRIVY_SCANNERS="${TRIVY_SCANNERS:-vuln}"
TRIVY_PKG_TYPES="${TRIVY_PKG_TYPES:-os}"
TRIVY_TIMEOUT="${TRIVY_TIMEOUT:-5m}"
```

Default local CI gates HIGH/CRITICAL OS package vulnerabilities. Teams can opt into library package scanning by setting `TRIVY_PKG_TYPES=os,library` in a runner where Trivy completes reliably.

### `deploy/k8s/deploy.sh`

Added service-driven deployment fields:

- `deploy.serviceType`
- `deploy.probes.readiness.initialDelaySeconds`
- `deploy.probes.readiness.periodSeconds`
- `deploy.probes.readiness.timeoutSeconds`
- `deploy.probes.liveness.initialDelaySeconds`
- `deploy.probes.liveness.periodSeconds`
- `deploy.probes.liveness.timeoutSeconds`

The base Kubernetes template remains generic; defaults are still provided by the deploy script.

### Kubernetes Template

`deploy/k8s/base/deployment.yaml` now renders explicit readiness and liveness timeout values from deploy configuration.

### CI/CD Config

Per-service Jenkinsfiles were added for both services.

The GitHub CI workflow was aligned so build and security scan use `REGISTRY`, while render/deploy still use `IMAGE_REGISTRY`. This prevents build/scan from using one image name while deployment renders another.

## Validation Commands

Run these from the platform repository root.

```bash
ci/validate-service.sh adservice
ci/validate-service.sh emailservice

ci/test.sh adservice
ci/test.sh emailservice

REGISTRY=local ci/build.sh adservice ci-local
REGISTRY=local ci/build.sh emailservice ci-local

REGISTRY=local ci/security.sh adservice ci-local
REGISTRY=local ci/security.sh emailservice ci-local
```

Observed results:

| Stage | adservice | emailservice |
| --- | --- | --- |
| Contract validation | Passed | Passed |
| Policy validation | Passed | Passed |
| Tests | Java compile/tests passed | Python unittest passed, 3 tests |
| Build | `local/adservice:ci-local` built | `local/emailservice:ci-local` built |
| Security scan | 0 HIGH/CRITICAL OS findings | 0 HIGH/CRITICAL OS findings |
| Service detection | Included | Included |
| Service matrix | Included | Included |

Discovery output included:

```text
adservice
currencyservice
emailservice
platform-smoke-test
productcatalogservice
```

Matrix output included:

```json
["adservice","currencyservice","emailservice","platform-smoke-test","productcatalogservice"]
```

## Jenkins Validation

Jenkins pipeline files:

- `services/adservice/Jenkinsfile`
- `services/emailservice/Jenkinsfile`

Pipeline model:

```text
Validate -> Test -> Build -> Security Scan -> Deploy Render
```

Stages call the reusable platform scripts:

```bash
ci/policy.sh <service>
ci/validate-service.sh <service>
ci/test.sh <service>
ci/build.sh <service> <tag>
ci/security.sh <service> <tag>
deploy/k8s/deploy.sh <service>
```

Failure found:

```text
Problem: Jenkinsfiles set IMAGE_REGISTRY but build/security scripts read REGISTRY.
Root cause: Deploy scripts and CI scripts use different variable names by design.
Fix: Added REGISTRY="${params.IMAGE_REGISTRY}" to both service Jenkinsfiles.
Re-run: The same build/security commands were rerun locally with REGISTRY=local and passed.
Confirmation: Images and rendered manifests now use local/<service>:ci-local consistently.
```

Execution note:

No Jenkins controller or Jenkins CLI was running locally during this pass. The Jenkinsfiles were created and their exact script stages were executed locally through the same `ci/*` and `deploy/k8s/*` scripts. Actual Jenkins controller execution still requires a Jenkins agent with Docker, Java 21, Python 3.12, yq, Trivy, and kubectl/minikube access.

## GitHub Actions Validation

Workflow:

- `.github/workflows/ci.yml`

Model:

```text
detect-services -> validate -> test -> build -> security scan -> deploy render
```

Fixes confirmed:

- Java setup uses Temurin 21.
- Python setup uses Python 3.12.
- Build step passes `REGISTRY: ${{ env.IMAGE_REGISTRY }}`.
- Security step passes `REGISTRY: ${{ env.IMAGE_REGISTRY }}`.
- Render step uses `deploy/k8s/deploy.sh`.

Failure found:

```text
Problem: GitHub CI build/security did not pass REGISTRY.
Root cause: build.sh/security.sh use REGISTRY, while workflow env used IMAGE_REGISTRY.
Fix: Added step-level REGISTRY env to Build and Security scan in .github/workflows/ci.yml.
Re-run: Local equivalent commands were rerun with REGISTRY=local and passed.
Confirmation: Rendered manifests reference local/adservice:ci-local and local/emailservice:ci-local.
```

Execution note:

No local GitHub Actions runner (`act`) or hosted GitHub execution was available in this workspace. YAML parsing was checked with `yq`; GitHub semantic linting with `actionlint` was not available.

## Hybrid Validation

Workflow:

- `.github/workflows/hybrid-build-test.yml`

Model:

```text
GitHub Actions -> validate/test/build/scan/push
Jenkins -> deploy with same SERVICE, IMAGE_REGISTRY, IMAGE_TAG
```

Artifact handoff:

```text
build/hybrid/jenkins-deploy.env
```

The hybrid workflow already passes `REGISTRY` into build and security stages. The Jenkins deploy side must consume the same metadata:

```text
SERVICE=<service>
ENV=dev
IMAGE_REGISTRY=<registry>
IMAGE_TAG=<sha-or-tag>
```

Validation status:

- The build/test/security script path was validated locally for both services.
- The deploy path was validated locally through `deploy/k8s/deploy.sh`.
- Hosted GitHub to Jenkins triggering requires configured Jenkins secrets and was not executed locally.

## Kubernetes Deployment

Local image preparation:

```powershell
& 'C:\Users\aquib\bin\minikube.exe' image load local/adservice:ci-local
& 'C:\Users\aquib\bin\minikube.exe' image load local/emailservice:ci-local
```

Deploy:

```bash
IMAGE_TAG=ci-local deploy/k8s/deploy.sh adservice
IMAGE_TAG=ci-local deploy/k8s/deploy.sh emailservice
```

Final pod state:

```text
adservice-6bb6f6d66-4rqcp      1/1 Running 0 restarts
emailservice-db8fbcf45-rsw7r   1/1 Running 0 restarts
```

Final service state:

```text
adservice      NodePort 80:30498/TCP
emailservice   NodePort 80:31438/TCP
```

Final endpoints:

```text
adservice      10.244.0.25:9555
emailservice   10.244.0.26:8080
```

Final probe evidence:

```text
adservice readiness: /ready on 9555, delay=20s, timeout=2s
adservice liveness:  /health on 9555, delay=30s, timeout=2s

emailservice readiness: /ready on 8080, delay=10s, timeout=2s
emailservice liveness:  /health on 8080, delay=30s, timeout=2s
```

Logs:

```text
adservice listening on 0.0.0.0:9555
emailservice listening on 0.0.0.0:8080
```

## Runtime Validation

`minikube service <service> -n dev --url` was attempted after converting both services to NodePort. In this Windows Docker/minikube environment, the command did not emit a URL and held the CLI process open. `minikube service list -n dev` showed both services with target port `http/80`, but URL values were empty.

Because the minikube CLI path did not provide a usable URL, endpoint checks were completed through `kubectl port-forward` against the deployed Kubernetes services.

adservice:

```text
GET /       -> {"service":"adservice","adCount":7,"protocol":"http","sourceProtocol":"grpc"}
GET /health -> {"status":"ok","service":"adservice"}
GET /ready  -> {"status":"ready","adCount":7}
```

emailservice:

```text
GET /       -> {"service":"emailservice","mode":"mock","protocol":"http","sourceProtocol":"grpc"}
GET /health -> {"status":"ok","service":"emailservice"}
GET /ready  -> {"status":"ready","mode":"mock"}
```

## Failure Debug Loop

### 1. Local Git Bash permission error

Problem:

```text
Git Bash validation initially hit a Windows CreateFileMapping permission failure in the sandbox.
```

Root cause:

```text
The local shell sandbox blocked Git Bash process behavior.
```

Fix:

```text
Reran the real scripts with approved elevated execution.
```

Re-run:

```bash
ci/validate-service.sh adservice
ci/validate-service.sh emailservice
ci/test.sh adservice
ci/test.sh emailservice
```

Confirmation:

```text
Both services passed contract validation and tests.
```

### 2. Trivy scan hang and cache lock

Problem:

```text
ci/security.sh adservice did not complete within 10 minutes.
Subsequent direct Trivy runs failed with a cache/database lock.
```

Root cause:

```text
Trivy remained stuck during local image/library analysis and held the cache lock.
```

Fix:

```text
Stopped the stale Trivy process, cleaned scan cache, and made the platform scanner default to bounded OS vulnerability scanning.
```

Re-run:

```bash
REGISTRY=local ci/security.sh adservice ci-local
REGISTRY=local ci/security.sh emailservice ci-local
```

Confirmation:

```text
Both scans completed and reported 0 HIGH/CRITICAL OS vulnerabilities.
```

### 3. Registry variable mismatch

Problem:

```text
Jenkins and GitHub CI could build/scan one image reference while deploy rendered another.
```

Root cause:

```text
ci/build.sh and ci/security.sh read REGISTRY. deploy/k8s/deploy.sh reads IMAGE_REGISTRY.
```

Fix:

```text
Added REGISTRY to service Jenkinsfiles and GitHub CI build/security steps.
```

Re-run:

```bash
REGISTRY=local ci/build.sh adservice ci-local
REGISTRY=local ci/security.sh adservice ci-local
REGISTRY=local ci/build.sh emailservice ci-local
REGISTRY=local ci/security.sh emailservice ci-local
```

Confirmation:

```text
Built and scanned images matched rendered Kubernetes image references.
```

### 4. Local image availability in minikube

Problem:

```text
Local Docker images are not automatically available inside the minikube node.
```

Root cause:

```text
Host Docker and minikube node image stores are separate in this environment.
```

Fix:

```powershell
& 'C:\Users\aquib\bin\minikube.exe' image load local/adservice:ci-local
& 'C:\Users\aquib\bin\minikube.exe' image load local/emailservice:ci-local
```

Re-run:

```bash
IMAGE_TAG=ci-local deploy/k8s/deploy.sh adservice
IMAGE_TAG=ci-local deploy/k8s/deploy.sh emailservice
```

Confirmation:

```text
kubectl describe pod showed "Container image ... already present on machine".
No ImagePullBackOff occurred after image load.
```

### 5. Readiness and liveness probe timeouts

Problem:

```text
adservice had early readiness timeouts.
emailservice restarted once when the local minikube node paused during service URL testing.
```

Root cause:

```text
The base template used fixed 1 second probe timeouts and service-specific startup/runtime tolerance was not configurable.
```

Fix:

```text
Added service.yml-driven probe timing fields and set 2 second timeouts for both services.
adservice also uses a 20 second readiness initial delay.
```

Re-run:

```bash
IMAGE_TAG=ci-local deploy/k8s/deploy.sh adservice
IMAGE_TAG=ci-local deploy/k8s/deploy.sh emailservice
kubectl describe pod -n dev -l app.kubernetes.io/instance=adservice
kubectl describe pod -n dev -l app.kubernetes.io/instance=emailservice
```

Confirmation:

```text
Fresh pods are Running 1/1 with 0 restarts and normal scheduling/start events.
```

### 6. `minikube service` URL unavailable

Problem:

```text
minikube service adservice -n dev --url and minikube service emailservice -n dev --url did not emit URLs.
```

Root cause:

```text
The local Windows Docker/minikube service URL path held the CLI process open and did not return a usable URL.
Direct node IP plus NodePort was also not reachable from the host.
```

Fix:

```text
Added service.yml-driven serviceType support and deployed both services as NodePort for local exposure.
For endpoint proof in this environment, used kubectl port-forward against the deployed Kubernetes services.
```

Re-run:

```bash
kubectl port-forward svc/adservice -n dev 8955:80
kubectl port-forward svc/emailservice -n dev 8808:80
```

Confirmation:

```text
/, /health, and /ready returned expected JSON for both services.
```

## Final Working Setup

From repo root:

```bash
ci/validate-service.sh adservice
ci/test.sh adservice
REGISTRY=local ci/build.sh adservice ci-local
REGISTRY=local ci/security.sh adservice ci-local

ci/validate-service.sh emailservice
ci/test.sh emailservice
REGISTRY=local ci/build.sh emailservice ci-local
REGISTRY=local ci/security.sh emailservice ci-local
```

Load images and deploy:

```powershell
& 'C:\Users\aquib\bin\minikube.exe' image load local/adservice:ci-local
& 'C:\Users\aquib\bin\minikube.exe' image load local/emailservice:ci-local
```

```bash
IMAGE_TAG=ci-local deploy/k8s/deploy.sh adservice
IMAGE_TAG=ci-local deploy/k8s/deploy.sh emailservice
```

Verify:

```bash
kubectl get pods -n dev -l app.kubernetes.io/instance=adservice -o wide
kubectl get pods -n dev -l app.kubernetes.io/instance=emailservice -o wide
kubectl get svc -n dev adservice emailservice -o wide
kubectl get endpoints -n dev adservice emailservice -o wide
kubectl describe pod -n dev -l app.kubernetes.io/instance=adservice
kubectl describe pod -n dev -l app.kubernetes.io/instance=emailservice
kubectl logs deployment/adservice -n dev
kubectl logs deployment/emailservice -n dev
```

Runtime:

```bash
kubectl port-forward svc/adservice -n dev 8955:80
kubectl port-forward svc/emailservice -n dev 8808:80
```

Then test:

```bash
curl http://127.0.0.1:8955/
curl http://127.0.0.1:8955/health
curl http://127.0.0.1:8955/ready

curl http://127.0.0.1:8808/
curl http://127.0.0.1:8808/health
curl http://127.0.0.1:8808/ready
```

## Engineer Onboarding Guide

To add the next service:

1. Create `services/<service-name>/`.
2. Add `Dockerfile`, `service.yml`, and `src/`.
3. Put all service-specific ports, probe paths, service type, and probe timing in `service.yml`.
4. Implement `GET /`, `GET /health`, and `GET /ready`.
5. Add service tests that run through `ci/test.sh`.
6. Build only through `ci/build.sh`.
7. Scan only through `ci/security.sh`.
8. Deploy only through `deploy/k8s/deploy.sh`.
9. Load local images into minikube before local Kubernetes deployment.
10. Validate pods, services, endpoints, logs, describes, and runtime endpoints.

Debug checklist:

- `Service not found`: verify `services/<service-name>/service.yml`.
- Missing port: check `docker.port`.
- Probe failures: confirm `/health` and `/ready`, then tune `deploy.probes`.
- Wrong image in manifest: align `REGISTRY`, `IMAGE_REGISTRY`, and `IMAGE_TAG`.
- `ImagePullBackOff`: run `minikube image load local/<service>:<tag>`.
- Namespace mismatch: confirm `K8S_NAMESPACE=dev` and inspect `kubectl get all -n dev`.
- `minikube service` hangs: check service type, run `minikube service list -n dev`, and use `kubectl port-forward` for deterministic local endpoint validation.

