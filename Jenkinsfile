pipeline {
  // No global agent: build stages get a Docker agent, deploy stages need no executor
  // while they wait for input (the linux-build node has a single executor).
  agent none

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
    stage('CI') {
      agent { docker { image 'node:20-alpine'; label 'linux-build' } }
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
        always { archiveArtifacts artifacts: 'npm-debug.log*', allowEmptyArchive: true }
      }
    }

    stage('Deploy - Staging') {
      when { branch 'develop' }
      steps { echo 'deploying to staging...' }
    }

    stage('Deploy - Production') {
      // beforeInput: evaluate the branch condition before pausing, or every branch would wait for approval
      when { branch 'main'; beforeInput true }
      input { message 'Deploy to production?' }
      steps { echo 'deploying to production...' }
    }
  }

  post {
    success { echo "✅ ${env.APP_NAME} passed on ${env.NODE_ENV} (${env.BRANCH_NAME})" }
    // Top-level post reports STAGE_NAME as "Declarative: Post Actions"; the failing
    // stage is captured in each stage's own post block instead.
    failure { echo "❌ Failed at stage: ${env.FAILED_STAGE ?: env.STAGE_NAME}" }
  }
}
