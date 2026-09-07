# ARMS Simulation Runbook Version 2: Branch Gated CI, Main as Source of Truth

## The model in plain words

Main branch is the only thing Argo CD watches. Nothing else exists to Argo CD.

Every new service or every change to an existing service happens on its own branch. Jenkins runs automatically on that branch and checks it. Only if every check passes can that branch be merged into main. If Jenkins fails, the merge is blocked at the platform level (GitHub or GitLab), so main never changes for that service, so Argo CD never sees anything, so that service is simply not deployed or not updated. Nothing needs to be manually stopped, the block happens automatically because merging is disabled.

Every service folder must contain a Dockerfile. This is now a required check, not optional.

---

## Step 1: Repository layout

```
repo
  services
    userservice
      Dockerfile
      src
      chart
        Chart.yaml
        values.yaml
        templates
    billingservice
      Dockerfile
      src
      chart
        Chart.yaml
        values.yaml
        templates
  Jenkinsfile
  applicationset.yaml
```

Every folder under services must contain a Dockerfile at all times. Jenkins will check for this on every branch.

## Step 2: Set the branch protection rule on main first

Do this before anything else so it is impossible to accidentally bypass it later.

1. Open your repository settings in GitHub or GitLab.
2. Click Branches.
3. Click Add rule, or Add branch protection rule.
4. Set the branch name pattern to main.
5. Enable Require status checks to pass before merging.
6. Search for and select the Jenkins check, it will appear once Jenkins has reported at least one status to the repository, so you may need to run the pipeline once first and come back to this step.
7. Enable Require branches to be up to date before merging.
8. Save the rule.

From this point forward, the merge button on any pull request targeting main is disabled until Jenkins reports success.

## Step 3: Create a multibranch pipeline job in Jenkins

A multibranch pipeline automatically detects every branch and every pull request and runs the Jenkinsfile against each one, which is what you need here.

1. Open Jenkins in your browser.
2. Click New Item.
3. Choose Multibranch Pipeline as the job type and give it a name, for example arms simulation.
4. Under Branch Sources, click Add source and choose Git or GitHub depending on where your repository lives.
5. Paste your repository URL and add credentials if the repository is private.
6. Under Behaviours, make sure Discover branches and Discover pull requests from origin are both enabled.
7. Under Build Configuration, set the script path to Jenkinsfile.
8. Save the job. Jenkins will scan the repository and create a sub job for every branch and every open pull request automatically.
9. Configure the webhook on your GitHub or GitLab repository to point at your Jenkins server so new branches and new commits trigger a scan immediately instead of waiting for the next periodic scan.

## Step 4: Write the Jenkinsfile

```groovy
pipeline {
    agent any
    stages {
        stage('Detect changed services') {
            steps {
                script {
                    def changed = sh(
                        script: "git diff --name-only origin/main...HEAD | grep '^services/' | cut -d/ -f2 | sort -u",
                        returnStdout: true
                    ).trim().split('\n')
                    env.CHANGED_SERVICES = changed.join(',')
                }
            }
        }
        stage('Required file check') {
            steps {
                sh 'test f services/SERVICE_NAME/Dockerfile'
                sh 'test f services/SERVICE_NAME/chart/Chart.yaml'
                sh 'test f services/SERVICE_NAME/chart/values.yaml'
            }
        }
        stage('Code standard check') {
            steps {
                sh 'run your linter here, for example eslint or checkstyle depending on the language'
            }
        }
        stage('Code cleanliness check') {
            steps {
                sh 'run your static analysis tool here, for example a sonar scanner command'
            }
        }
        stage('Manifest validation') {
            steps {
                sh 'helm lint services/SERVICE_NAME/chart'
                sh 'helm template services/SERVICE_NAME/chart | kubeconform strict summary'
            }
        }
        stage('Build image from branch') {
            steps {
                sh 'docker build t your registry SERVICE_NAME BRANCH_COMMIT services/SERVICE_NAME'
                sh 'docker push your registry SERVICE_NAME BRANCH_COMMIT'
            }
        }
        stage('Update tag on this branch only') {
            steps {
                sh 'yq i .image.tag equals BRANCH_COMMIT services/SERVICE_NAME/chart/values.yaml'
                sh 'git commit am ci update SERVICE_NAME tag on branch'
                sh 'git push origin HEAD'
            }
        }
    }
}
```

Notice the tag update in the final stage is pushed to the current branch, not to main. Main only receives this change once the pull request is actually merged. This is what keeps the deployment blocked until merge happens.

Note: a small number of command line flags shown above require the dash character as part of their required syntax, for example docker build with its t flag, git commit with its am flag, and test with its f flag. These are unavoidable tool syntax and are written here in plain words, but you will type them using the standard flag format for that tool.

## Step 5: Open a pull request for every change

1. After pushing your branch, open a pull request targeting main in GitHub or GitLab.
2. Jenkins will automatically pick up the pull request because Discover pull requests from origin was enabled in step 3.
3. Watch the pull request page, a status check from Jenkins will appear and update as the pipeline runs.
4. If every stage passes, the check turns green and the merge button becomes available.
5. If any stage fails, the check turns red and the merge button stays disabled, exactly as configured in step 2.

## Step 6: Set up Argo CD to watch main only

1. Create a file named applicationset.yaml with the following content.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: services appset
  namespace: argocd
spec:
  generators:
    git:
      repoURL: your repository url
      revision: main
      directories:
        path: services/*
  template:
    metadata:
      name: path.basename
    spec:
      project: arms simulation
      source:
        repoURL: your repository url
        targetRevision: main
        path: path/chart
        helm:
          valueFiles:
            values.yaml
      destination:
        server: https kubernetes default svc
        namespace: your namespace
      syncPolicy:
        automated:
          selfHeal: true
          prune: true
```

2. Apply it using kubectl apply f applicationset.yaml
3. Confirm in the Argo CD user interface under Applications that one Application exists per service folder currently present on main.

## Step 7: Test the full flow end to end

1. Create a new branch and add a new service folder including a Dockerfile.
2. Push the branch and open a pull request targeting main.
3. Confirm Jenkins runs automatically and every stage passes.
4. Confirm the merge button becomes available and merge the pull request.
5. Confirm a new Argo CD Application appears for the new service and a pod is created.
6. Make a change on a new branch to an existing service.
7. Repeat the same pull request flow and confirm only that one service updates once merged, while every other service is untouched.

## Step 8: Test the failure case specifically

1. Create a branch for a service folder that is missing its Dockerfile on purpose.
2. Push the branch and open a pull request targeting main.
3. Confirm the Required file check stage fails.
4. Confirm the pull request shows a red status check and the merge button is disabled.
5. Confirm main is completely unchanged and Argo CD shows no new activity at all for that service.
6. This confirms the safety rule for this version of the setup: a failing branch can never reach main, so Argo CD can never see it, so that service is never deployed.