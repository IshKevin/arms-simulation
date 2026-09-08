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
