pipeline {
    agent {
        docker {
          // image 'rockylinux:9'
          image 'buildready-rocky'
          args '-u root'
        }
    }
    stages {
        // stage('Show environment') {
        //     steps {
        //         sh 'cat /etc/os-release'
        //         sh 'pwd'
        //         sh 'ls -la'
        //     }
        // }
        stage('Check tooling') {
            steps {
                sh 'dnf install -y which || echo "oh wow, probably no dnf, wtf"'
                sh 'which git && git --version || echo "git not found"'
                sh 'gcc --version || echo "gcc not found"'
            }
        }
        stage('Run script') {
            steps {
                
               sh 'echo verify where we are; ls -alh'
               sh 'mkdir -p ./coot-build'
               sh 'cd ./coot-build'
               sh 'echo now, the real build...; ls -alh; ls -alh ..'
               sh 'bash ../GPhL_script/dl_and_build_coot_cv-20260319.sh -os -distro -noninteractive'
            }
        }
    }
}
