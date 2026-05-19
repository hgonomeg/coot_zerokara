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
               sh 'mkdir -p ./coot-build'
               sh '. /opt/rh/gcc-toolset-15/enable; cd ./coot-build; echo now, the real build...; ls -alh; ls -alh ..; bash ../GPhL_script/dl_and_build_coot_cv-20260319.sh -os -distro -noninteractive'
               archiveArtifacts artifacts: 'coot-build/coot-*.tar.gz', fingerprint: true
            }
            post {
                failure {
                    echo "Build failed"
                }
                always {
                    archiveArtifacts artifacts: 'coot-build/build/*.log*', fingerprint: true, allowEmptyArchive: true
                    archiveArtifacts artifacts: 'coot-build/deps/*.log*', fingerprint: true, allowEmptyArchive: true
                    archiveArtifacts artifacts: 'coot-build/build/*/*.log*', fingerprint: true, allowEmptyArchive: true
                    archiveArtifacts artifacts: 'coot-build/deps/*/*.log*', fingerprint: true, allowEmptyArchive: true
                    cleanWs()
                }
            }
        }
    }
}
