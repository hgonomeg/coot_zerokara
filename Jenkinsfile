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
        stage('Check tooling') {
            steps {
                sh 'dnf install -y which || echo "oh wow, probably no dnf, wtf"'
                
                sh 'which git && git --version || echo "git not found"'
                sh 'gcc --version || echo "gcc not found"'
            }
        }
    }
}
