pipeline {
  agent { docker { image 'node:20-alpine'; label 'linux-build' } }

  environment {
    APP_NAME = 'taskflow-api'
    NODE_ENV = 'test'
  }

  options {
    // A hung npm install or test run (network stall, open handle keeping Jest alive)
    // would hold the executor forever and starve every queued build behind it.
    // A hard timeout frees the executor and turns a silent hang into a visible failure.
    timeout(time: 10, unit: 'MINUTES')
  }

  stages {
    stage('Install') { steps { sh 'npm ci' } }
    stage('Lint') { steps { sh 'npm run lint' } }
    stage('Unit Test') {
      steps {
        echo "Testing ${env.APP_NAME} with NODE_ENV=${env.NODE_ENV}"
        sh 'npm test'
      }
    }
  }

  post {
    success { echo "✅ ${env.APP_NAME} passed on ${env.NODE_ENV}" }
    failure { echo "❌ Failed at stage: ${env.STAGE_NAME}" }
    always { archiveArtifacts artifacts: 'npm-debug.log*', allowEmptyArchive: true }
  }
}
