// Runs kubectl in a container on the kind docker network; needs $KUBECONFIG (file credential) in scope.
def kubectl(String args) {
  return sh(script: "docker run --rm -i --network kind -v \"$KUBECONFIG\":/kube/config:ro -e KUBECONFIG=/kube/config registry.k8s.io/kubectl:v1.31.0 ${args}", returnStdout: true).trim()
}

pipeline {
  // No global agent: build stages get a Docker agent, waiting stages need no executor
  // (the linux-build node has a single executor).
  agent none

  parameters {
    // Lab 06 demo switch: false lets a critical CVE pass the SCA stage so the OPA policy gate can be shown blocking on its own
    string(name: 'BASE_IMAGE', defaultValue: 'node:20-alpine', description: 'Lab 07 demo: base image for the container build (use an old image to trip the Trivy gate)')
    booleanParam(name: 'BROKEN_IMAGE', defaultValue: false, description: 'Lab 07 demo: deploy a non-existent image tag to trigger the automatic rollback')
    booleanParam(name: 'SCA_BLOCK', defaultValue: true, description: 'Fail the SCA stage on critical vulnerabilities')
  }

  environment {
    APP_NAME = 'taskflow-api'
    NODE_ENV = 'test'
  }

  options {
    // A hung npm install or test run (network stall, open handle keeping Jest alive)
    // would hold the executor forever and starve every queued build behind it.
    // A hard timeout frees the executor and turns a silent hang into a visible failure.
    timeout(time: 45, unit: 'MINUTES')
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

    stage('Secrets Detection') {
      agent { label 'linux-build' }
      steps {
        // Scans the full history reachable from HEAD (all commits of this branch), not just the working tree
        sh '''
          docker run --rm -v "$WORKSPACE":/repo -w /repo zricethezav/gitleaks:latest             detect --source . --log-opts="HEAD" --report-format json --report-path gitleaks-report.json --exit-code 1
        '''
      }
      post {
        always { archiveArtifacts artifacts: 'gitleaks-report.json', allowEmptyArchive: true }
        failure { script { env.FAILED_STAGE = env.STAGE_NAME } }
      }
    }

    stage('SAST') {
      parallel {
        stage('ESLint Security') {
          agent { docker { image 'node:20-alpine'; label 'linux-build' } }
          steps {
            sh 'npm ci'
            sh 'npx eslint --plugin security src/ -f @microsoft/eslint-formatter-sarif -o eslint.sarif'
          }
          post { always { archiveArtifacts artifacts: 'eslint.sarif', allowEmptyArchive: true } }
        }
        stage('Semgrep') {
          agent { label 'linux-build' }
          steps {
            sh '''
              docker run --rm -v "$WORKSPACE":/src -w /src semgrep/semgrep:latest                 semgrep scan --config=p/owasp-top-ten --config=p/nodejs --sarif --output semgrep.sarif --error src
            '''
          }
          post { always { archiveArtifacts artifacts: 'semgrep.sarif', allowEmptyArchive: true } }
        }
      }
      post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
    }

    stage('SCA - npm audit') {
      agent { docker { image 'node:20-alpine'; label 'linux-build' } }
      steps {
        script {
          sh 'npm ci && (npm audit --audit-level=high --json > audit.json || true)'
          // node instead of jq: the node image ships no jq
          def critical = sh(
            script: "node -p \"require('./audit.json').metadata.vulnerabilities.critical\"",
            returnStdout: true
          ).trim().toInteger()
          def high = sh(
            script: "node -p \"require('./audit.json').metadata.vulnerabilities.high\"",
            returnStdout: true
          ).trim().toInteger()
          if (high > 0) { echo "WARNING: ${high} high vulnerabilities (warn only)" }
          if (critical > 0 && params.SCA_BLOCK) {
            error("Blocking: ${critical} critical vulnerabilities found")
          }
          echo "SCA finished: ${critical} critical, ${high} high (only critical blocks)"
        }
      }
      post {
        always { archiveArtifacts artifacts: 'audit.json', allowEmptyArchive: true }
        failure { script { env.FAILED_STAGE = env.STAGE_NAME } }
      }
    }

    stage('Generate SBOM') {
      agent { label 'linux-build' }
      steps {
        sh '''
          docker run --rm -v "$WORKSPACE":/w -w /w anchore/syft:latest             dir:. --exclude ./node_modules -o cyclonedx-json=taskflow-api.cdx.json
          # local throwaway keypair (lab): sign the SBOM, archive SBOM + signature + public key
          rm -f cosign.key cosign.pub
          # cosign refuses an empty key password; use a random per-build one (the key is deleted after signing)
          export COSIGN_PASSWORD=$(head -c 24 /dev/urandom | base64)
          docker run --rm -u 0 -e COSIGN_PASSWORD -v "$WORKSPACE":/w -w /w ghcr.io/sigstore/cosign/cosign:v2.4.1             generate-key-pair
          docker run --rm -u 0 -e COSIGN_PASSWORD -v "$WORKSPACE":/w -w /w ghcr.io/sigstore/cosign/cosign:v2.4.1             sign-blob --yes --key cosign.key --output-signature taskflow-api.cdx.json.sig taskflow-api.cdx.json
          rm -f cosign.key
        '''
      }
      post {
        always { archiveArtifacts artifacts: 'taskflow-api.cdx.json,taskflow-api.cdx.json.sig,cosign.pub', allowEmptyArchive: true }
        failure { script { env.FAILED_STAGE = env.STAGE_NAME } }
      }
    }

    stage('Policy Gate') {
      agent { label 'linux-build' }
      steps {
        sh '''
          docker run --rm -v "$WORKSPACE":/w -w /w openpolicyagent/opa:latest-static             eval --fail-defined -i audit.json -d policy/security.rego 'data.security.deny[_]'
        '''
      }
      post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
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

    stage('Build Image') {
      agent { label 'linux-build' }
      steps {
        script {
          // Immutable tag = short commit SHA, never "latest"
          env.IMAGE_TAG = sh(script: 'git rev-parse --short=7 HEAD', returnStdout: true).trim()
          env.IMAGE = "localhost:5001/taskflow-api:${env.IMAGE_TAG}"
        }
        sh 'docker build --build-arg BASE=${BASE_IMAGE} -t $IMAGE .'
        sh 'docker push $IMAGE'
      }
      post { failure { script { env.FAILED_STAGE = env.STAGE_NAME } } }
    }

    stage('Container Scan') {
      agent { label 'linux-build' }
      steps {
        sh '''
          docker run --rm -v /var/run/docker.sock:/var/run/docker.sock -v trivy-cache:/root/.cache \
            -v "$WORKSPACE":/w aquasec/trivy:latest image \
            --exit-code 1 --severity HIGH,CRITICAL --format sarif -o /w/trivy.sarif $IMAGE
        '''
      }
      post {
        always { archiveArtifacts artifacts: 'trivy.sarif', allowEmptyArchive: true }
        failure { script { env.FAILED_STAGE = env.STAGE_NAME } }
      }
    }

    stage('Blue/Green Deploy') {
      // main only; a plain (non-multibranch) job has no BRANCH_NAME
      when { anyOf { branch 'main'; expression { env.BRANCH_NAME == null } } }
      agent { label 'linux-build' }
      steps {
        withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
          script {
            def current = kubectl("get svc taskflow -o jsonpath='{.spec.selector.color}'")
            def next = current == 'blue' ? 'green' : 'blue'
            env.PREV_COLOR = current
            def image = params.BROKEN_IMAGE ? 'localhost:5001/taskflow-api:does-not-exist' : env.IMAGE
            kubectl("set image deployment/taskflow-${next} app=${image}")
            kubectl("rollout status deployment/taskflow-${next} --timeout=60s")
            // smoke test the new pods through their own Service, bypassing the live one
            kubectl("run smoke-${BUILD_NUMBER} --rm -i --restart=Never --image-pull-policy=IfNotPresent --image=curlimages/curl -- curl -sf http://taskflow-${next}:8080/health")
            kubectl("patch svc taskflow -p '{\"spec\":{\"selector\":{\"color\":\"${next}\"}}}'")
            echo "Switched traffic from ${current} to ${next}"
          }
        }
      }
      post {
        failure {
          // automated rollback: point the live Service back at the previous color
          withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
            script {
              env.FAILED_STAGE = env.STAGE_NAME
              if (env.PREV_COLOR) {
                kubectl("patch svc taskflow -p '{\"spec\":{\"selector\":{\"color\":\"${env.PREV_COLOR}\"}}}'")
                echo "ROLLBACK: traffic stays on ${env.PREV_COLOR}"
              }
            }
          }
        }
      }
    }
  }

  post {
    success { echo "✅ ${env.APP_NAME} passed on ${env.NODE_ENV}" }
    // Top-level post reports STAGE_NAME as "Declarative: Post Actions"; the failing
    // stage is captured in each stage's own post block instead.
    failure { echo "❌ Failed at stage: ${env.FAILED_STAGE ?: env.STAGE_NAME}" }
  }
}
