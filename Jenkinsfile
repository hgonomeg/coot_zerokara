pipeline {
    agent {
        docker { image 'rockylinux:9.3' }
    }
    stages {
        stage('Show environment') {
            steps {
                sh 'cat /etc/os-release'
                sh 'pwd'
                sh 'ls -la'
            }
        }
        stage('Check tooling') {
            steps {
                sh 'which git || echo "git not found"'
                sh 'gcc --version || echo "gcc not found"'
            }
        }
    }
}
