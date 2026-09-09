# ARMS Simulation Runbook Version 2: Branch Gated CI, Main as Source of Truth

## The model in plain words

Main branch is the only thing Argo CD watches. Nothing else exists to Argo CD.

Every new service or every change to an existing service happens on its own branch. Jenkins runs automatically on that branch and checks it, but **only when that branch has an open pull request targeting main** — Jenkins does not run its full pipeline on ordinary branch pushes with no PR. Only if every check passes can that branch be merged into main. If Jenkins fails, the merge is blocked at the platform level (GitHub or GitLab), so main never changes for that service, so Argo CD never sees anything, so that service is simply not deployed or not updated. Nothing needs to be manually stopped, the block happens automatically because merging is disabled.

Jenkins is CI only. It builds, lints, validates, and pushes an image, and bumps the chart's image tag on the branch — it never touches the cluster, never runs `kubectl` or `argocd`, and holds no cluster credentials. Deployment is entirely Argo CD's job, watching main via GitOps.

Every service is Python. Every service folder must contain a Dockerfile and a `requirements.txt`. This is now a required check, not optional.

---

## Step 1: Repository layout

```
repo
  services
    userservice
      Dockerfile
      requirements.txt
      src
      chart
        Chart.yaml
        values.yaml
        templates
    billingservice
      Dockerfile
      requirements.txt
      src
      chart
        Chart.yaml
        values.yaml
        templates
  Jenkinsfile
  appproject.yaml
  applicationset.yaml
```

Every folder under `services` must contain a `Dockerfile` and a `requirements.txt` at all times. Jenkins checks for both on every pull request targeting main.

## Step 2: Set the branch protection rule on main first

Do this before anything else so it is impossible to accidentally bypass it later.

1. Open your repository settings in GitHub or GitLab.
2. Click Branches.
3. Click Add rule, or Add branch protection rule.
4. Set the branch name pattern to main.
5. Enable Require status checks to pass before merging.
6. Search for and select the Jenkins check, it will appear once Jenkins has reported at least one status to the repository, so you may need to open a pull request once first and come back to this step.
7. Enable Require branches to be up to date before merging.
8. Save the rule.

From this point forward, the merge button on any pull request targeting main is disabled until Jenkins reports success.

## Step 3: Create a multibranch pipeline job in Jenkins

A multibranch pipeline automatically detects every branch and every pull request and runs the Jenkinsfile against each one, which is what you need here.

1. Open Jenkins in your browser.
2. Click New Item.
3. Choose Multibranch Pipeline as the job type and give it a name, for example `arms-simulation`.
4. Under Branch Sources, click Add source and choose Git or GitHub depending on where your repository lives.
5. Paste your repository URL and add credentials if the repository is private.
6. Under Behaviours, make sure Discover branches and Discover pull requests from origin are both enabled. The Jenkinsfile itself skips full execution unless the build is a pull request targeting main, so plain branch pushes still get scanned but won't run the heavy stages.
7. Under Build Configuration, set the script path to Jenkinsfile.
8. Save the job. Jenkins will scan the repository and create a sub job for every branch and every open pull request automatically.
9. Configure the webhook on your GitHub or GitLab repository to point at your Jenkins server so new branches and new commits trigger a scan immediately instead of waiting for the next periodic scan.

## Step 4: The Jenkinsfile

The working pipeline lives in the repository root at `Jenkinsfile`. Summary of what it does, per pull request targeting main:

1. **Verify PR targets main** — any build that isn't a PR against main is marked `NOT_BUILT` and stops immediately.
2. **Detect changed services** — diffs against `origin/main` to find every folder under `services/` touched by this branch (there can be more than one).
3. For **each** changed service, in a loop:
   - **Required file check** — `Dockerfile`, `chart/Chart.yaml`, `chart/values.yaml`, `requirements.txt` must all exist.
   - **Install dependencies** — creates a virtualenv, installs `requirements.txt` plus `flake8`/`pylint`.
   - **Code standard check** — `flake8` (PEP8/style).
   - **Code cleanliness check** — `pylint` (static analysis).
   - **Manifest validation** — `helm lint` and `helm template | kubeconform`, both purely local/offline checks against the chart — no cluster is contacted.
   - **Build and push image** — tags the image with the short commit SHA and pushes it to `REGISTRY` (set this at the top of the Jenkinsfile, or wire it to your real registry — Docker Hub, ECR, GHCR, etc.). Requires a Jenkins credential named `registry-credentials`.
   - **Update tag on this branch** — bumps `chart/values.yaml`'s `image.tag` and pushes back to the *same branch* (never to main). Requires a Jenkins SSH credential named `git-ssh-credentials` with push access.

Notice the tag update is pushed to the current branch, not to main. Main only receives this change once the pull request is actually merged. This is what keeps the deployment blocked until merge happens, and it's the only mechanism that reaches source control — Jenkins never deploys anything itself.

Before running this for real, set in the Jenkinsfile:
- `REGISTRY` — your actual container registry path.
- Create Jenkins credentials `registry-credentials` (username/password) and `git-ssh-credentials` (SSH key with push access to the repo).

## Step 5: Open a pull request for every change

1. After pushing your branch, open a pull request targeting main in GitHub or GitLab.
2. Jenkins will automatically pick up the pull request because Discover pull requests from origin was enabled in step 3.
3. Watch the pull request page, a status check from Jenkins will appear and update as the pipeline runs.
4. If every stage passes, the check turns green and the merge button becomes available.
5. If any stage fails, the check turns red and the merge button stays disabled, exactly as configured in step 2.

## Step 6: Install and configure Argo CD

> **Cluster-admin required.** Installing Argo CD creates a `argocd` namespace plus cluster-scoped CRDs and ClusterRoles. If your account is scoped to a single namespace (as `kevin`'s RBAC was earlier confirmed to be — no permission to create namespaces), you cannot do this step yourself. Ask your cluster admin to run it, or to confirm Argo CD is already installed before you continue.

1. Create the namespace and install Argo CD:
   ```bash
   kubectl create namespace argocd
   kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   kubectl -n argocd rollout status deployment/argocd-server
   ```
2. Retrieve the initial admin password:
   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
   ```
3. Access the UI/API locally via port-forward (same pattern used earlier in this environment for other services):
   ```bash
   kubectl port-forward svc/argocd-server -n argocd 8081:443
   ```
   Then open `https://localhost:8081` in a browser (a self-signed certificate warning is expected), or use the CLI:
   ```bash
   argocd login localhost:8081 --username admin --password <password-from-step-2> --insecure
   argocd account update-password
   ```
4. Register the git repository so Argo CD can read it (adjust for HTTPS + token vs SSH key depending on your repo host):
   ```bash
   argocd repo add <GIT_REPO_URL> --ssh-private-key-path ~/.ssh/id_rsa
   ```

## Step 7: Create the Argo CD AppProject

The ApplicationSet in the next step deploys into a project named `arms-simulation`. That project has to exist first, or Argo CD rejects every generated Application with "project not found".

1. Fill in `<GIT_REPO_URL>` in `appproject.yaml` at the repository root.
2. Apply it:
   ```bash
   kubectl apply -f appproject.yaml
   ```
3. Confirm it exists: `argocd proj get arms-simulation`.

## Step 8: Set up the ApplicationSet to watch main only

1. Fill in `<GIT_REPO_URL>` in `applicationset.yaml` at the repository root (same file referenced in Step 1's layout). It targets the `kevin` namespace and the `arms-simulation` project created in Step 7.
2. Apply it:
   ```bash
   kubectl apply -f applicationset.yaml
   ```
3. Confirm in the Argo CD UI (or `argocd app list`) that one Application exists per service folder currently present on main.

## Step 9: Test the full flow end to end

1. Create a new branch and add a new service folder including a `Dockerfile` and `requirements.txt`.
2. Push the branch and open a pull request targeting main.
3. Confirm Jenkins runs automatically and every stage passes.
4. Confirm the merge button becomes available and merge the pull request.
5. Confirm a new Argo CD Application appears for the new service and a pod is created in the `kevin` namespace.
6. Make a change on a new branch to an existing service.
7. Repeat the same pull request flow and confirm only that one service updates once merged, while every other service is untouched.

## Step 10: Test the failure case specifically

1. Create a branch for a service folder that is missing its `Dockerfile` on purpose.
2. Push the branch and open a pull request targeting main.
3. Confirm the Required file check stage fails.
4. Confirm the pull request shows a red status check and the merge button is disabled.
5. Confirm main is completely unchanged and Argo CD shows no new activity at all for that service.
6. This confirms the safety rule for this version of the setup: a failing branch can never reach main, so Argo CD can never see it, so that service is never deployed.
