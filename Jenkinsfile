pipeline {
    agent {
        docker {
          // image 'rockylinux:9'
          image 'buildready-rocky'
          args '-u root'
        }
    }
    // todo: change this to a matrix, going over multiple distros
    stages {
        stage('Set build info') {
            steps {
                script {
                    // fix stupid error "fatal: detected dubious ownership in repository at /var/jenkins_home/workspace/coot_zerokara"
                    sh 'git config --global --add safe.directory "*"'
                    def commit = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                    def msg = sh(script: 'git log -1 --pretty=%s', returnStdout: true).trim()
                    def branch = env.GIT_BRANCH?.replaceFirst('^origin/', '') ?: 'unknown'
                    currentBuild.displayName = "#${env.BUILD_NUMBER} [${branch}] ${commit}: ${msg}"
                    currentBuild.description = "${env.GIT_BRANCH}: ${msg}"
                }
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
                    archiveArtifacts artifacts: 'coot-build/coot*/*.log*', fingerprint: true, allowEmptyArchive: true
                    // Fix Jenkins permissions issue
                    sh 'chown -R 1000:1000 .'
                    cleanWs()
                }
            }
        }
    }
}
