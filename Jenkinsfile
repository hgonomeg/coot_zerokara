pipeline {
    agent {
        docker {
          image 'rockylinux:9'
          args '-u root'
        }
    }
    stages {
        stage('Show environment') {
            steps {
                sh 'cat /etc/os-release'
                sh 'pwd'
                sh 'ls -la'
            }
        }
        stage('Diagnose') {
            steps {
                sh 'id'
                sh 'cat /etc/resolv.conf'
                sh 'curl -sI https://dl.rockylinux.org/pub/rocky/9/BaseOS/x86_64/os/ || echo "curl failed"'
                sh 'timeout 30 dnf -y --setopt=*.skip_if_unavailable=true install -y which || echo "dnf failed"'
            }
        }
        stage('Check tooling') {
            steps {
                sh 'dnf install -y which || echo "oh wow, probably no dnf, wtf"'
                
                sh 'which git && git --version || echo "git not found"'
                sh 'gcc --version || echo "gcc not found"'
            }
        }
    }
}
