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
    stage('Install') {
      steps { sh 'npm ci' }
      post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
    }
    stage('Lint') {
      steps { sh 'npm run lint' }
      post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
    }
    stage('Unit Test') {
      steps {
        echo "Testing ${env.APP_NAME} with NODE_ENV=${env.NODE_ENV}"
        sh 'npm test'
      }
      post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
    }
  }

  post {
    success { echo "✅ ${env.APP_NAME} passed on ${env.NODE_ENV}" }
    // In the top-level post, STAGE_NAME is "Declarative: Post Actions", so the failing
    // stage is captured in each stage's own post block (where STAGE_NAME is correct).
    failure { echo "❌ Failed at stage: ${env.FAILED_STAGE ?: env.STAGE_NAME}" }
    always { archiveArtifacts artifacts: 'npm-debug.log*', allowEmptyArchive: true }
  }
}
