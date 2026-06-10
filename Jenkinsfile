pipeline {
    agent {
        docker {
          // image 'rockylinux:9'
          image 'buildready-rocky'
          args '-u root'
        }
    }
    options {
        buildDiscarder(logRotator(numToKeepStr: '50', artifactNumToKeepStr: '30'))
    }
    environment {
        COOT_GIT = 'https://github.com/hgonomeg/coot'
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
        // Full from-scratch build (no caching) run as the script's four phases, one stage
        // each. The first stage installs the OS packages; later stages reuse them via
        // -no-use-os-package-manager. Each sh re-sources the gcc-toolset enable script.
        stage('Download sources') {
            steps {
               sh 'mkdir -p ./coot-build'
               sh '. /opt/rh/gcc-toolset-15/enable; cd ./coot-build; bash ../dl_and_build_coot.sh -use-os-package-manager -distributable -noninteractive -download-only'
            }
        }
        stage('Build toolchain') {
            steps {
               sh '. /opt/rh/gcc-toolset-15/enable; cd ./coot-build; bash ../dl_and_build_coot.sh -no-use-os-package-manager -distributable -noninteractive -toolchain-only'
            }
        }
        stage('Build dependencies') {
            steps {
               sh '. /opt/rh/gcc-toolset-15/enable; cd ./coot-build; bash ../dl_and_build_coot.sh -no-use-os-package-manager -distributable -noninteractive -deps-only'
            }
        }
        stage('Build Coot') {
            steps {
               sh '. /opt/rh/gcc-toolset-15/enable; cd ./coot-build; bash ../dl_and_build_coot.sh -no-use-os-package-manager -distributable -noninteractive -coot-stage-only'
               archiveArtifacts artifacts: 'coot-build/coot-*.tar.gz', fingerprint: true
            }
        }
    }
    post {
        failure {
            echo "Build failed"
        }
        always {
            archiveArtifacts artifacts: 'coot-build/*.log*', fingerprint: true, allowEmptyArchive: true
            archiveArtifacts artifacts: 'coot-build/build/*.log*', fingerprint: true, allowEmptyArchive: true
            archiveArtifacts artifacts: 'coot-build/deps/*.log*', fingerprint: true, allowEmptyArchive: true
            archiveArtifacts artifacts: 'coot-build/build/*/*.log*', fingerprint: true, allowEmptyArchive: true
            archiveArtifacts artifacts: 'coot-build/deps/*/*.log*', fingerprint: true, allowEmptyArchive: true
            archiveArtifacts artifacts: 'coot-build/coot*/*.log*', fingerprint: true, allowEmptyArchive: true
            archiveArtifacts artifacts: 'coot-build/coot*/chapi-build/*.log*', fingerprint: true, allowEmptyArchive: true
            // Fix Jenkins permissions issue
            sh 'chown -R 1000:1000 .'
            cleanWs()
        }
    }
}
