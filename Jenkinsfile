pipeline {
    agent any

    environment {
        // The rest of this project lives in eu-west-1 (Ireland), but ECR
        // Public's control-plane API only exists in us-east-1 — that's an
        // AWS platform constraint, not a mismatch with the project region.
        // Pulled images are still served globally regardless.
        ECR_PUBLIC_REGION = 'us-east-1'

        // No AWS keys stored here or anywhere in this public repo: the
        // Jenkins EC2 instance has an IAM instance role (see iac-jenkins/iam.tf)
        // granted ECR Public permissions, so the `aws` CLI picks up temporary
        // credentials automatically from the instance metadata service.

        // Jenkins credential ID (Manage Jenkins > Credentials) — create this
        // before running the pipeline for real. This only stores an ID string
        // in this public repo; the actual token stays in Jenkins' credential
        // store and is never exposed.
        GIT_CREDENTIALS_ID = 'git-https-credentials' // Username/password: GitHub username / personal access token
    }

    // This pipeline is CI only: build, lint, validate, push the image to ECR
    // Public, and bump the chart's image tag on the branch. It never touches
    // the cluster and never runs `kubectl`/`argocd` — deployment is entirely
    // Argo CD's job once a change lands on main.
    stages {
        stage('Verify PR targets main') {
            when {
                not { changeRequest target: 'main' }
            }
            steps {
                script {
                    currentBuild.result = 'NOT_BUILT'
                    error('Skipping: this pipeline only runs for pull requests targeting main.')
                }
            }
        }

        stage('Detect changed services') {
            when {
                changeRequest target: 'main'
            }
            steps {
                script {
                    sh 'git fetch origin main'
                    def changed = sh(
                        script: "git diff --name-only origin/main...HEAD | grep '^services/' | cut -d/ -f2 | sort -u || true",
                        returnStdout: true
                    ).trim()
                    env.CHANGED_SERVICES = changed
                    echo changed ? "Changed services: ${changed}" : 'No service changes detected.'
                }
            }
        }

        stage('Process changed services') {
            when {
                allOf {
                    changeRequest target: 'main'
                    expression { return env.CHANGED_SERVICES?.trim() }
                }
            }
            steps {
                script {
                    def services = env.CHANGED_SERVICES.split('\n')
                    def commitSha = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()

                    for (svc in services) {
                        def svcPath = "services/${svc}"
                        def venv = "${svcPath}/.venv"
                        def repoUri = ''

                        stage("${svc}: Required file check") {
                            sh "test -f ${svcPath}/Dockerfile"
                            sh "test -f ${svcPath}/chart/Chart.yaml"
                            sh "test -f ${svcPath}/chart/values.yaml"
                            sh "test -f ${svcPath}/requirements.txt"
                        }

                        stage("${svc}: Install dependencies") {
                            sh """
                                python3 -m venv ${venv}
                                . ${venv}/bin/activate
                                pip install --upgrade pip
                                pip install -r ${svcPath}/requirements.txt
                                pip install flake8 pylint
                            """
                        }

                        stage("${svc}: Code standard check") {
                            // PEP8 / style
                            sh """
                                . ${venv}/bin/activate
                                flake8 ${svcPath}/src
                            """
                        }

                        stage("${svc}: Code cleanliness check") {
                            // Static analysis / code smells
                            sh """
                                . ${venv}/bin/activate
                                pylint ${svcPath}/src
                            """
                        }

                        stage("${svc}: Manifest validation") {
                            // Local chart/schema validation only — no cluster contacted.
                            sh "helm lint ${svcPath}/chart"
                            sh "helm template ${svcPath}/chart | kubeconform -strict -summary"
                        }

                        stage("${svc}: Ensure ECR Public repo exists") {
                            // Credentials come from the Jenkins EC2 instance's
                            // IAM role — nothing stored or exposed here.
                            sh "aws ecr-public describe-repositories --repository-names ${svc} --region ${ECR_PUBLIC_REGION} || aws ecr-public create-repository --repository-name ${svc} --region ${ECR_PUBLIC_REGION}"
                            repoUri = sh(
                                script: "aws ecr-public describe-repositories --repository-names ${svc} --region ${ECR_PUBLIC_REGION} --query 'repositories[0].repositoryUri' --output text",
                                returnStdout: true
                            ).trim()
                        }

                        stage("${svc}: Build and push image") {
                            sh """
                                aws ecr-public get-login-password --region ${ECR_PUBLIC_REGION} | docker login --username AWS --password-stdin public.ecr.aws
                                docker build -t ${repoUri}:${commitSha} ${svcPath}
                                docker push ${repoUri}:${commitSha}
                            """
                        }

                        stage("${svc}: Update tag on this branch") {
                            // Pushes only to this branch, never to main — main only
                            // changes when the pull request is actually merged, which
                            // is what keeps Argo CD from deploying an unreviewed change.
                            withCredentials([usernamePassword(
                                credentialsId: env.GIT_CREDENTIALS_ID,
                                usernameVariable: 'GIT_USER',
                                passwordVariable: 'GIT_TOKEN'
                            )]) {
                                script {
                                    def originUrl = sh(script: 'git remote get-url origin', returnStdout: true).trim()
                                    def repoPath = originUrl
                                        .replaceFirst('^https://', '')
                                        .replaceFirst('^git@github\\.com:', 'github.com/')
                                    sh """
                                        yq -i '.image.repository = "${repoUri}"' ${svcPath}/chart/values.yaml
                                        yq -i '.image.tag = "${commitSha}"' ${svcPath}/chart/values.yaml
                                        git config user.email 'jenkins@ci.local'
                                        git config user.name 'jenkins-ci'
                                        git commit -am 'ci: update ${svc} image to ${repoUri}:${commitSha} on branch'
                                        git push https://${GIT_USER}:${GIT_TOKEN}@${repoPath} HEAD:${env.BRANCH_NAME}'
                                    """
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
