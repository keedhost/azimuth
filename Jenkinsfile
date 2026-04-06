// ─────────────────────────────────────────────────────────────────────────────
// Jenkinsfile — Azimuth (Garmin Connect IQ)  [Declarative Pipeline]
// ─────────────────────────────────────────────────────────────────────────────
//
// Необхідні credentials (Jenkins → Manage Jenkins → Credentials):
//   DEVELOPER_KEY  — Secret file, містить developer_key.der
//   CIQ_SDK_URL    — Secret text, повний URL Linux-SDK
//   GH_TOKEN       — Secret text, GitHub Personal Access Token
//                    (scopes: repo → contents:write)
//
// Необхідна змінна середовища агента або pipeline:
//   GH_REPO        — репозиторій у форматі "owner/repo", напр. "myorg/Azimuth"
//
// Необхідні плагіни:
//   - Pipeline, Credentials Binding
//
// Публікація артефактів:
//   Будь-яка гілка  → Jenkins artifact (посилання в UI)
//   main / master   → GitHub Release "nightly" (pre-release, оновлюється)
//   тег v*.*.*      → GitHub Release з changelog та SHA256SUMS
// ─────────────────────────────────────────────────────────────────────────────

pipeline {

    agent {
        label 'linux'
    }

    parameters {
        string(
            name: 'TEST_DEVICE',
            defaultValue: 'fenix7',
            description: 'Пристрій для smoke-збірки'
        )
        booleanParam(
            name: 'BUILD_MATRIX',
            defaultValue: false,
            description: 'Збирати для всіх пристроїв матриці'
        )
        string(
            name: 'GH_REPO',
            defaultValue: '',
            description: 'GitHub repo у форматі owner/repo (перекриває змінну оточення)'
        )
    }

    environment {
        CIQ_SDK_DIR    = "${WORKSPACE}/.ciq-sdk"
        MATRIX_DEVICES = 'fenix7 fenix7x fenix7s fr265 fr265s epix2 instinct2 venu3'
    }

    stages {

        // ── 1. Checkout ────────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        // ── 2. Java ────────────────────────────────────────────────────────
        stage('Setup Java') {
            steps {
                sh '''
                    if ! command -v java &>/dev/null; then
                        sudo apt-get update -q
                        sudo apt-get install -y openjdk-17-jdk
                    fi
                    java -version
                '''
            }
        }

        // ── 3. gh CLI ──────────────────────────────────────────────────────
        stage('Setup gh CLI') {
            steps {
                sh '''
                    if command -v gh &>/dev/null; then
                        echo "gh already installed: $(gh --version | head -1)"
                        exit 0
                    fi
                    echo "Installing gh CLI..."
                    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
                        | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
                    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
                        https://cli.github.com/packages stable main" \
                        | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
                    sudo apt-get update -q
                    sudo apt-get install -y gh
                    gh --version
                '''
            }
        }

        // ── 4. Connect IQ SDK ──────────────────────────────────────────────
        stage('Install Connect IQ SDK') {
            steps {
                script {
                    def sdkExists = fileExists("${env.CIQ_SDK_DIR}/bin/monkeyc")
                    if (!sdkExists) {
                        withCredentials([string(credentialsId: 'CIQ_SDK_URL', variable: 'SDK_URL')]) {
                            sh '''
                                curl -fsSL "${SDK_URL}" -o /tmp/ciq-sdk.zip
                                mkdir -p "${CIQ_SDK_DIR}"
                                unzip -q /tmp/ciq-sdk.zip -d "${CIQ_SDK_DIR}"
                                rm /tmp/ciq-sdk.zip
                                chmod +x "${CIQ_SDK_DIR}/bin/"*
                            '''
                        }
                    } else {
                        echo "SDK cached at ${env.CIQ_SDK_DIR}"
                    }
                }
                sh '"${CIQ_SDK_DIR}/bin/monkeyc" --version'
            }
        }

        // ── 5. Smoke build ─────────────────────────────────────────────────
        stage('Smoke Build') {
            steps {
                withCredentials([file(credentialsId: 'DEVELOPER_KEY', variable: 'KEY_FILE')]) {
                    sh '''
                        "${CIQ_SDK_DIR}/bin/monkeyc" \
                            -f monkey.jungle \
                            -o "Azimuth-${TEST_DEVICE}.prg" \
                            -d "${TEST_DEVICE}" \
                            -y "${KEY_FILE}" \
                            -w
                    '''
                }
            }
        }

        // ── 6. IQ package ──────────────────────────────────────────────────
        stage('Build IQ Package') {
            steps {
                withCredentials([file(credentialsId: 'DEVELOPER_KEY', variable: 'KEY_FILE')]) {
                    sh '''
                        "${CIQ_SDK_DIR}/bin/monkeyc" \
                            -f monkey.jungle \
                            -o Azimuth.iq \
                            -e \
                            -y "${KEY_FILE}" \
                            -w
                        ls -lh Azimuth.iq
                    '''
                }
            }
        }

        // ── 7. Matrix build ────────────────────────────────────────────────
        stage('Matrix Build') {
            when {
                expression { params.BUILD_MATRIX == true }
            }
            steps {
                withCredentials([file(credentialsId: 'DEVELOPER_KEY', variable: 'KEY_FILE')]) {
                    script {
                        def devices = env.MATRIX_DEVICES.trim().split(' ')
                        def parallelStages = [:]
                        devices.each { device ->
                            def d = device
                            parallelStages["Build ${d}"] = {
                                sh """
                                    "${CIQ_SDK_DIR}/bin/monkeyc" \
                                        -f monkey.jungle \
                                        -o "Azimuth-${d}.prg" \
                                        -d "${d}" \
                                        -y "${KEY_FILE}" \
                                        -w
                                    echo "  ${d}: OK"
                                """
                            }
                        }
                        parallel parallelStages
                    }
                }
            }
        }

        // ── 8. Checksum ────────────────────────────────────────────────────
        stage('Generate Checksum') {
            steps {
                sh '''
                    sha256sum Azimuth.iq > SHA256SUMS.txt
                    # Додати PRG-файли якщо є
                    if ls Azimuth-*.prg 1>/dev/null 2>&1; then
                        sha256sum Azimuth-*.prg >> SHA256SUMS.txt
                    fi
                    echo "=== SHA256SUMS.txt ==="
                    cat SHA256SUMS.txt
                '''
            }
        }

        // ── 9. Archive (Jenkins) ───────────────────────────────────────────
        stage('Archive Artifacts') {
            steps {
                archiveArtifacts(
                    artifacts: 'Azimuth.iq, Azimuth-*.prg, SHA256SUMS.txt',
                    allowEmptyArchive: false,
                    fingerprint: true
                )
            }
        }

        // ── 10. Publish to GitHub Releases ────────────────────────────────
        stage('Publish Release') {
            when {
                anyOf {
                    branch 'main'
                    branch 'master'
                    // Тег у форматі v1.2.3
                    tag pattern: '^v\\d+\\.\\d+\\.\\d+$', comparator: 'REGEXP'
                }
            }
            steps {
                withCredentials([string(credentialsId: 'GH_TOKEN', variable: 'GH_TOKEN')]) {
                    script {
                        // Визначаємо репозиторій
                        def repo = params.GH_REPO?.trim()
                        if (!repo) {
                            repo = env.GH_REPO ?: ''
                        }
                        if (!repo) {
                            // Спробувати витягти з git remote
                            repo = sh(
                                script: "git remote get-url origin | sed 's|.*github.com[:/]||;s|\\.git$||'",
                                returnStdout: true
                            ).trim()
                        }
                        echo "GitHub repo: ${repo}"

                        def isTag = (env.TAG_NAME != null && env.TAG_NAME ==~ /^v\d+\.\d+\.\d+$/)

                        if (isTag) {
                            // ── Версійний реліз ───────────────────────────
                            def version = env.TAG_NAME
                            def buildDate = sh(script: "date -u '+%Y-%m-%d %H:%M UTC'", returnStdout: true).trim()

                            def notes = """## Azimuth ${version}

**Дата збірки:** ${buildDate}
**Система збірки:** Jenkins #${env.BUILD_NUMBER}

### Як встановити
1. Завантажте \`Azimuth.iq\`
2. Підключіть годинник до ПК
3. Відкрийте Garmin Express → **Manage Apps** → **Install from File**

### Підтримувані пристрої
fenix 6/7, Forerunner 245/255/265/945, Epix 2, Instinct 2, Venu 2/3 та інші.

### Перевірка цілісності
\`\`\`
sha256sum -c SHA256SUMS.txt
\`\`\`"""

                            writeFile file: 'RELEASE_NOTES.md', text: notes

                            sh """
                                GH_TOKEN="${GH_TOKEN}" gh release create "${version}" \
                                    --repo "${repo}" \
                                    --title "Azimuth ${version}" \
                                    --notes-file RELEASE_NOTES.md \
                                    Azimuth.iq \
                                    Azimuth-*.prg \
                                    SHA256SUMS.txt
                            """
                            echo "Published release: ${version}"

                        } else {
                            // ── Nightly реліз ─────────────────────────────
                            def buildDate = sh(script: "date -u '+%Y-%m-%d %H:%M UTC'", returnStdout: true).trim()
                            def shortSha  = env.GIT_COMMIT?.take(7) ?: 'unknown'

                            def notes = """## Nightly Build

| | |
|---|---|
| **Гілка** | \`${env.BRANCH_NAME}\` |
| **Commit** | \`${shortSha}\` |
| **Дата** | ${buildDate} |
| **Jenkins Build** | #${env.BUILD_NUMBER} |

### Як встановити
1. Завантажте \`Azimuth.iq\`
2. Підключіть годинник до ПК
3. Відкрийте Garmin Express → **Manage Apps** → **Install from File**

### Перевірка цілісності
\`\`\`
sha256sum -c SHA256SUMS.txt
\`\`\`

> ⚠️ Нічна збірка може бути нестабільною."""

                            writeFile file: 'RELEASE_NOTES.md', text: notes

                            sh """
                                # Видалити попередній nightly
                                GH_TOKEN="${GH_TOKEN}" gh release delete nightly \
                                    --repo "${repo}" --yes --cleanup-tag 2>/dev/null || true

                                GH_TOKEN="${GH_TOKEN}" gh release create nightly \
                                    --repo "${repo}" \
                                    --title "Nightly Build — ${buildDate}" \
                                    --notes-file RELEASE_NOTES.md \
                                    --prerelease \
                                    Azimuth.iq \
                                    Azimuth-*.prg \
                                    SHA256SUMS.txt
                            """
                            echo "Published nightly release."
                        }

                        // Cleanup temp file
                        sh 'rm -f RELEASE_NOTES.md'
                    }
                }
            }
        }
    }

    post {
        always {
            sh 'rm -f developer_key.der RELEASE_NOTES.md || true'
        }
        success {
            script {
                def isTag = (env.TAG_NAME != null && env.TAG_NAME ==~ /^v\d+\.\d+\.\d+$/)
                def isMaster = (env.BRANCH_NAME == 'main' || env.BRANCH_NAME == 'master')
                if (isTag) {
                    echo "Release ${env.TAG_NAME} published to GitHub."
                } else if (isMaster) {
                    echo "Nightly release published to GitHub."
                } else {
                    echo "Build artifacts archived in Jenkins."
                }
            }
        }
        failure {
            echo "Build FAILED — artifacts were NOT published."
        }
    }
}
