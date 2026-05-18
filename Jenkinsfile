pipeline {
    agent {
        docker { image 'rockylinux:9.3' }
    }
    stages {
        stage('Show environment') {
            steps {
                sh 'echo hello world'
                sh 'sigh...'
                sh 'cat /etc/os-release'
                sh 'pwd'
                sh 'ls -la'
            }
        }
        stage('Check tooling') {
            steps {
                sh 'sudo dnf install -y which || echo "oh wow, probably no sudo (access)"'
                
                sh 'which git || echo "git not found"'
                sh 'gcc --version || echo "gcc not found"'
            }
        }
    }
}
