pipeline {
    agent any

    options {
        disableConcurrentBuilds()
    }

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
    }

    // This pipeline is CI only: build, lint, validate, and push the image to
    // ECR Public. It never writes to git and never touches the cluster or
    // runs `kubectl`/`argocd`. Deployment config (Helm charts) lives in the
    // separate arms-simulation-infra repo — Argo CD Image Updater watches
    // ECR for new tags and writes them into that repo; Argo CD deploys from
    // there. Jenkins has no involvement in either of those steps.
    stages {
        stage('Detect changed services') {
            when {
                changeRequest target: 'main'
            }
            steps {
                script {
                    // PR builds only fetch the PR's own ref (refs/pull/N/head), not
                    // the full branch refspec, so plain `git fetch origin main`
                    // updates FETCH_HEAD but never creates a ref literally named
                    // origin/main. Fetch it into an explicit ref so the diff below
                    // can actually resolve it.
                    sh 'git fetch origin main:refs/remotes/origin/main'
                    def diffStatus = sh(
                        script: 'git diff --name-only origin/main...HEAD > /tmp/changed_files.txt',
                        returnStatus: true
                    )
                    if (diffStatus != 0) {
                        error("git diff against origin/main failed (exit ${diffStatus}) — cannot safely determine changed services.")
                    }
                    def changed = sh(
                        script: "grep '^services/' /tmp/changed_files.txt | cut -d/ -f2 | sort -u || true",
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
                            // Pipeline ends here. Argo CD Image Updater picks up
                            // the new tag from ECR on its own polling schedule —
                            // nothing further for Jenkins to do.
                            sh """
                                aws ecr-public get-login-password --region ${ECR_PUBLIC_REGION} | docker login --username AWS --password-stdin public.ecr.aws
                                docker build -t ${repoUri}:${commitSha} ${svcPath}
                                docker push ${repoUri}:${commitSha}
                            """
                        }
                    }
                }
            }
        }
    }
}
