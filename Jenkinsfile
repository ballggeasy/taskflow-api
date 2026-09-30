// taskflow-api capstone pipeline (Labs 03-09 composed).
// Code -> Commit -> Build -> Test -> Stage -> Deploy -> Monitor
//
// - Independent checks run in parallel; dependent stages (build -> scan -> deploy) stay sequential.
// - Build/test stages run in ephemeral Kubernetes pods (Lab 09). Stages that need the Docker
//   daemon (gitleaks, image build, Trivy, E2E, kubectl) run on the docker-capable node
//   `linux-build`, because the kind cluster has no Docker daemon to hand to a pod.
// - No secret values appear in this file: everything comes from Jenkins credentials.

// Runs kubectl in a container on the kind network; needs $KUBECONFIG (file credential) in scope.
def kubectl(String args) {
  return sh(script: "docker run --rm -i --network kind -v \"\$KUBECONFIG\":/kube/config:ro -e KUBECONFIG=/kube/config registry.k8s.io/kubectl:v1.31.0 ${args}", returnStdout: true).trim()
}

// Slack-format message with branch and build URL, posted to the lab's mock Slack webhook
def notify(String status) {
  def branch = env.BRANCH_NAME ?: 'main'
  def text = "${status}: taskflow-api ${branch} #${env.BUILD_NUMBER} ${env.BUILD_URL}"
  node('k8s-node') {
    container('node') {
      sh "wget -qO- --header='Content-Type: application/json' --post-data='{\"text\": \"${text}\"}' http://notify-mock:8000/ || true"
    }
  }
}

def nodePod = '''
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: node
    image: node:20-alpine
    imagePullPolicy: IfNotPresent
    command: ['cat']
    tty: true
  - name: jnlp
    image: jenkins/inbound-agent:latest-jdk21
    imagePullPolicy: IfNotPresent
'''

pipeline {
  agent none

  parameters {
    string(name: 'BASE_IMAGE', defaultValue: 'node:20-alpine', description: 'Base image for the container build')
    booleanParam(name: 'BROKEN_IMAGE', defaultValue: false, description: 'Demo: deploy a non-existent image tag to trigger the automatic rollback')
    booleanParam(name: 'SCA_BLOCK', defaultValue: true, description: 'Fail the SCA stage on critical vulnerabilities')
    string(name: 'HEALTH_THRESHOLD', defaultValue: '0.9', description: 'Minimum pipeline success rate required before deploying to production')
  }

  environment {
    APP_NAME = 'taskflow-api'
    NODE_ENV = 'test'
  }

  options {
    // A hung install, scan or rollout must not hold an executor or pod forever.
    timeout(time: 60, unit: 'MINUTES')
  }

  stages {
    // Fail fast: cheapest and most damaging check first
    stage('Secrets Detection') {
      agent { label 'linux-build' }
      steps {
        sh '''
          docker run --rm -v "$WORKSPACE":/repo -w /repo zricethezav/gitleaks:latest \
            detect --source . --log-opts="HEAD" --report-format json --report-path gitleaks-report.json --exit-code 1
        '''
      }
      post { always { archiveArtifacts artifacts: 'gitleaks-report.json', allowEmptyArchive: true } }
    }

    stage('Verify') {
      parallel {
        stage('Lint') {
          agent { kubernetes { yaml nodePod; defaultContainer 'node' } }
          steps {
            sh 'npm ci'
            sh 'npm run lint'
          }
        }
        stage('Unit Test') {
          agent { kubernetes { yaml nodePod; defaultContainer 'node' } }
          steps {
            sh 'npm ci'
            sh 'npm test -- --coverage --reporters=jest-junit'
          }
          post {
            always {
              junit 'reports/junit.xml'
              recordCoverage tools: [[parser: 'COBERTURA', pattern: 'coverage/cobertura-coverage.xml']]
              stash name: 'coverage', includes: 'coverage/**,sonar-project.properties,src/**,tests/**', allowEmpty: true
            }
          }
        }
        stage('SAST - ESLint security') {
          agent { kubernetes { yaml nodePod; defaultContainer 'node' } }
          steps {
            sh 'npm ci'
            sh 'npx eslint --plugin security src/ -f @microsoft/eslint-formatter-sarif -o eslint.sarif'
          }
          post { always { archiveArtifacts artifacts: 'eslint.sarif', allowEmptyArchive: true } }
        }
        stage('SCA - npm audit') {
          agent { kubernetes { yaml nodePod; defaultContainer 'node' } }
          steps {
            script {
              sh 'npm ci && (npm audit --audit-level=high --json > audit.json || true)'
              def critical = sh(script: "node -p \"require('./audit.json').metadata.vulnerabilities.critical\"", returnStdout: true).trim().toInteger()
              def high = sh(script: "node -p \"require('./audit.json').metadata.vulnerabilities.high\"", returnStdout: true).trim().toInteger()
              if (high > 0) { echo "WARNING: ${high} high vulnerabilities (warn only)" }
              if (critical > 0 && params.SCA_BLOCK) {
                error("Blocking: ${critical} critical vulnerabilities found")
              }
              echo "SCA finished: ${critical} critical, ${high} high (only critical blocks)"
            }
          }
          post {
            always {
              archiveArtifacts artifacts: 'audit.json', allowEmptyArchive: true
              stash name: 'audit', includes: 'audit.json', allowEmpty: true
            }
          }
        }
      }
    }

    stage('Deep Scan') {
      parallel {
        stage('SAST - Semgrep') {
          agent { label 'linux-build' }
          steps {
            sh '''
              docker run --rm -v "$WORKSPACE":/src -w /src semgrep/semgrep:latest \
                semgrep scan --config=p/owasp-top-ten --config=p/nodejs --sarif --output semgrep.sarif --error src
            '''
          }
          post { always { archiveArtifacts artifacts: 'semgrep.sarif', allowEmptyArchive: true } }
        }
        stage('Generate SBOM') {
          agent { label 'linux-build' }
          steps {
            sh '''
              docker run --rm -v "$WORKSPACE":/w -w /w anchore/syft:latest \
                dir:. --exclude ./node_modules -o cyclonedx-json=taskflow-api.cdx.json
              rm -f cosign.key cosign.pub
              # random per-build key password; the private key is deleted right after signing
              export COSIGN_PASSWORD=$(head -c 24 /dev/urandom | base64)
              docker run --rm -u 0 -e COSIGN_PASSWORD -v "$WORKSPACE":/w -w /w ghcr.io/sigstore/cosign/cosign:v2.4.1 generate-key-pair
              docker run --rm -u 0 -e COSIGN_PASSWORD -v "$WORKSPACE":/w -w /w ghcr.io/sigstore/cosign/cosign:v2.4.1 \
                sign-blob --yes --key cosign.key --output-signature taskflow-api.cdx.json.sig taskflow-api.cdx.json
              rm -f cosign.key
            '''
          }
          post { always { archiveArtifacts artifacts: 'taskflow-api.cdx.json,taskflow-api.cdx.json.sig,cosign.pub', allowEmptyArchive: true } }
        }
      }
    }

    stage('Policy Gate') {
      agent { label 'linux-build' }
      steps {
        unstash 'audit'
        sh '''
          docker run --rm -v "$WORKSPACE":/w -w /w openpolicyagent/opa:latest-static \
            eval --fail-defined -i audit.json -d policy/security.rego 'data.security.deny[_]'
        '''
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
    }

    stage('Quality Gate') {
      steps {
        timeout(time: 5, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
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
        sh 'docker build --build-arg BASE=${BASE_IMAGE:-node:20-alpine} -t $IMAGE .'
        sh 'docker push $IMAGE'
      }
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
      post { always { archiveArtifacts artifacts: 'trivy.sarif', allowEmptyArchive: true } }
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
      }
    }

    stage('Deploy - Staging') {
      when { branch 'develop' }
      steps { echo 'deploying to staging...' }
    }

    // Aborts the production deploy while the pipeline itself is unhealthy (success rate of recent builds below the threshold), as reported by Prometheus.
    stage('Pipeline Health Gate') {
      when { expression { env.BRANCH_NAME == null || env.BRANCH_NAME == 'main' } }
      agent { kubernetes { yaml nodePod; defaultContainer 'node' } }
      steps {
        script {
          def job = env.JOB_NAME.replace('/', '%2F')
          // Jenkins' own health score (percentage of the recent builds that succeeded) as exposed by the Prometheus plugin
          def q = "default_jenkins_builds_health_score{jenkins_job=\"${env.JOB_NAME}\"} / 100"
          def url = "http://prometheus:9090/api/v1/query?query=" + java.net.URLEncoder.encode(q, 'UTF-8')
          def rate = sh(script: "wget -qO- '${url}' | node -e \"const d=JSON.parse(require('fs').readFileSync(0,'utf8'));console.log(d.data.result.length?parseFloat(d.data.result[0].value[1]).toFixed(3):'0')\"", returnStdout: true).trim().toDouble()
          echo "Pipeline success rate from Prometheus: ${rate} (required: ${params.HEALTH_THRESHOLD ?: '0.9'})"
          if (rate < (params.HEALTH_THRESHOLD ?: '0.9').toDouble()) {
            error("Pipeline Health Gate: success rate ${rate} is below ${params.HEALTH_THRESHOLD ?: '0.9'}; refusing to deploy to production")
          }
        }
      }
    }

    stage('Deploy - Production') {
      // main only; a plain (non-multibranch) job has no BRANCH_NAME
      when { expression { env.BRANCH_NAME == null || env.BRANCH_NAME == 'main' } }
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
    success { script { notify('SUCCESS') } }
    failure { script { notify('FAILURE') } }
  }
}
