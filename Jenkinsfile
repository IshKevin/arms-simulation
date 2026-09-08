pipeline {
    agent any

    // This pipeline is CI only: build, lint, validate, and build a local image.
    // It never touches the cluster, never runs `kubectl`/`argocd`, and never
    // pushes anything back to git — deployment is entirely Argo CD's job once
    // a change lands on main.
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

                        stage("${svc}: Build image") {
                            // No registry configured yet — build locally to validate
                            // the Dockerfile, but don't push anywhere.
                            sh "docker build -t ${svc}:${commitSha} ${svcPath}"
                        }
                    }
                }
            }
        }
    }
}
