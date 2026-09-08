pipeline {
    agent any

    environment {
        // Every service under services/ is Python. Point this at your real
        // registry (Docker Hub, ECR, GHCR, ...).
        //REGISTRY = 'REPLACE_WITH_YOUR_REGISTRY'

        // Jenkins credentials IDs (Manage Jenkins > Credentials) — create these
        // before running the pipeline for real.
       // REGISTRY_CREDENTIALS_ID = 'registry-credentials'
        //GIT_SSH_CREDENTIALS_ID  = 'git-ssh-credentials'
    }

    // This pipeline is CI only: build, lint, validate, push an image, and bump
    // the chart's image tag on the current branch. It never touches the
    // cluster and never runs `kubectl`/`argocd` — deployment is entirely
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

                        stage("${svc}: Build and push image") {
                            withCredentials([usernamePassword(
                                credentialsId: env.REGISTRY_CREDENTIALS_ID,
                                usernameVariable: 'REG_USER',
                                passwordVariable: 'REG_PASS'
                            )]) {
                                sh """
                                    echo "\$REG_PASS" | docker login ${REGISTRY} -u "\$REG_USER" --password-stdin
                                    docker build -t ${REGISTRY}/${svc}:${commitSha} ${svcPath}
                                    docker push ${REGISTRY}/${svc}:${commitSha}
                                """
                            }
                        }

                        stage("${svc}: Update tag on this branch") {
                            // Pushes only to this branch, never to main — main only
                            // changes when the pull request is actually merged, which
                            // is what keeps Argo CD from deploying an unreviewed change.
                            sshagent([env.GIT_SSH_CREDENTIALS_ID]) {
                                sh """
                                    yq -i '.image.tag = "${commitSha}"' ${svcPath}/chart/values.yaml
                                    git config user.email 'jenkins@ci.local'
                                    git config user.name 'jenkins-ci'
                                    git commit -am 'ci: update ${svc} tag to ${commitSha} on branch'
                                    git push origin HEAD:${env.BRANCH_NAME}
                                """
                            }
                        }
                    }
                }
            }
        }
    }
}
