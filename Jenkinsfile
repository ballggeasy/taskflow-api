pipeline {
  // No global agent: build stages get a Docker agent, waiting stages need no executor
  // (the linux-build node has a single executor).
  agent none

  environment {
    APP_NAME = 'taskflow-api'
    NODE_ENV = 'test'
  }

  options {
    // A hung npm install or test run (network stall, open handle keeping Jest alive)
    // would hold the executor forever and starve every queued build behind it.
    // A hard timeout frees the executor and turns a silent hang into a visible failure.
    timeout(time: 30, unit: 'MINUTES')
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
            sh 'npm test -- --coverage --reporters=jest-junit'
          }
          post {
            always {
              junit 'reports/junit.xml'
              recordCoverage tools: [[parser: 'COBERTURA', pattern: 'coverage/cobertura-coverage.xml']]
              stash name: 'coverage', includes: 'coverage/**,sonar-project.properties,src/**,tests/**', allowEmpty: true
            }
            failure { script { env.FAILED_STAGE = env.STAGE_NAME } }
          }
        }
      }
      post {
        always { archiveArtifacts artifacts: 'npm-debug.log*', allowEmptyArchive: true }
      }
    }

    stage('SonarQube Analysis') {
      agent { docker { image 'sonarsource/sonar-scanner-cli:latest'; label 'linux-build'; args '-u root' } }
      steps {
        unstash 'coverage'
        withSonarQubeEnv('SonarQube') {
          sh 'sonar-scanner -Dsonar.projectKey=taskflow-api'
        }
      }
      post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
    }

    stage('Quality Gate') {
      steps {
        timeout(time: 5, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
      post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
    }

    stage('E2E') {
      agent { label 'linux-build' }
      environment { COMPOSE_PROJECT_NAME = "taskflow-e2e-${env.BUILD_NUMBER}" }
      steps {
        checkout scm
        sh 'docker compose up -d --build --wait'
        sh '''
          docker run --rm --network ${COMPOSE_PROJECT_NAME}_default \
            -v "$WORKSPACE":/work -w /work -e API_URL=http://api:8080 \
            mcr.microsoft.com/playwright:v1.49.1-jammy \
            sh -c "npm ci && npx playwright test -c e2e/playwright.config.js"
        '''
      }
      post {
        always {
          sh 'docker compose down -v || true'
          junit allowEmptyResults: true, testResults: 'reports/e2e-junit.xml'
          archiveArtifacts artifacts: 'playwright-report/**', allowEmptyArchive: true
        }
        failure { script { env.FAILED_STAGE = env.STAGE_NAME } }
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
    success { echo "✅ ${env.APP_NAME} passed on ${env.NODE_ENV}" }
    // Top-level post reports STAGE_NAME as "Declarative: Post Actions"; the failing
    // stage is captured in each stage's own post block instead.
    failure { echo "❌ Failed at stage: ${env.FAILED_STAGE ?: env.STAGE_NAME}" }
  }
}
