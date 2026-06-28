#!/bin/bash
# blfs/12-install-java-dev.sh
# Java Development Tools Installation for LFS/BLFS

set -e

log_info()  { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success(){ echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_error()  { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

# Répertoires : utilise le même chemin que le builder
SOURCES_DIR="/output/sources"
INSTALL_DIR="/opt"
JAVA_HOME="/opt/jdk"
MAVEN_HOME="/opt/maven"
GRADLE_HOME="/opt/gradle"
TOMCAT_HOME="/opt/tomcat"
JENKINS_HOME="/opt/jenkins"
DOCKER_HOME="/opt/docker"

mkdir -p "$SOURCES_DIR" "$INSTALL_DIR"
cd "$SOURCES_DIR"

# ============================================================================
# 1. Install OpenJDK (Eclipse Temurin 21 LTS)
# ============================================================================
install_java() {
    log_info "Installing Eclipse Temurin JDK 21..."
    JDK_FILE="OpenJDK21U-jdk_x64_alpine-linux_hotspot_21.0.9_10.tar.gz"
    JDK_URL="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.9%2B10/${JDK_FILE}"

    if [ ! -f "$SOURCES_DIR/$JDK_FILE" ]; then
        log_info "Downloading JDK..."
        sudo wget -q "$JDK_URL" -O "$SOURCES_DIR/$JDK_FILE"
    fi

    # Extraire avec sudo dans /opt
    sudo tar -xzf "$SOURCES_DIR/$JDK_FILE" -C "$INSTALL_DIR"
    EXTRACTED_DIR=$(tar -tf "$SOURCES_DIR/$JDK_FILE" | head -1 | cut -d/ -f1)
    sudo mv "$INSTALL_DIR/$EXTRACTED_DIR" "$JAVA_HOME"

    # Variables d'environnement (accessibles à tous)
    sudo tee /etc/profile.d/java.sh << 'EOF' > /dev/null
export JAVA_HOME=/opt/jdk
export PATH=$JAVA_HOME/bin:$PATH
EOF

    sudo chmod +x /etc/profile.d/java.sh
    source /etc/profile.d/java.sh

    log_success "Java installed: $(java -version 2>&1 | head -n1)"
}

# ============================================================================
# 2. Install Apache Maven
# ============================================================================
install_maven() {
    log_info "Installing Apache Maven..."
    MVN_FILE="apache-maven-3.9.16-src.tar.gz"
    MVN_URL="https://dlcdn.apache.org/maven/maven-3/3.9.16/source/${MVN_FILE}"

    if [ ! -f "$SOURCES_DIR/$MVN_FILE" ]; then
        log_info "Downloading Maven..."
        sudo wget -q "$MVN_URL" -O "$SOURCES_DIR/$MVN_FILE"
    fi

    sudo tar -xzf "$SOURCES_DIR/$MVN_FILE" -C "$INSTALL_DIR"
    EXTRACTED_DIR=$(tar -tf "$SOURCES_DIR/$MVN_FILE" | head -1 | cut -d/ -f1)
    sudo mv "$INSTALL_DIR/$EXTRACTED_DIR" "$MAVEN_HOME"

    sudo tee /etc/profile.d/maven.sh << 'EOF' > /dev/null
export MAVEN_HOME=/opt/maven
export PATH=$MAVEN_HOME/bin:$PATH
EOF

    sudo chmod +x /etc/profile.d/maven.sh
    log_success "Maven installed"
}

# ============================================================================
# 3. Install Gradle
# ============================================================================
install_gradle() {
    log_info "Installing Gradle..."
    GRADLE_FILE="gradle-8.14-bin.zip"
    GRADLE_URL="https://services.gradle.org/distributions/${GRADLE_FILE}"

    if [ ! -f "$SOURCES_DIR/$GRADLE_FILE" ]; then
        log_info "Downloading Gradle..."
        sudo wget -q "$GRADLE_URL" -O "$SOURCES_DIR/$GRADLE_FILE"
    fi

    sudo unzip -q "$SOURCES_DIR/$GRADLE_FILE" -d "$INSTALL_DIR"
    EXTRACTED_DIR=$(unzip -l "$SOURCES_DIR/$GRADLE_FILE" | head -4 | tail -1 | awk '{print $4}' | cut -d/ -f1)
    sudo mv "$INSTALL_DIR/$EXTRACTED_DIR" "$GRADLE_HOME"

    sudo tee /etc/profile.d/gradle.sh << 'EOF' > /dev/null
export GRADLE_HOME=/opt/gradle
export PATH=$GRADLE_HOME/bin:$PATH
EOF

    sudo chmod +x /etc/profile.d/gradle.sh
    log_success "Gradle installed"
}

# ============================================================================
# 4. Install Apache Tomcat
# ============================================================================
install_tomcat() {
    log_info "Installing Apache Tomcat..."
    TOMCAT_FILE="apache-tomcat-10.1.56.tar.gz"
    TOMCAT_URL="https://dlcdn.apache.org/tomcat/tomcat-10/v10.1.56/bin/${TOMCAT_FILE}"

    if [ ! -f "$SOURCES_DIR/$TOMCAT_FILE" ]; then
        log_info "Downloading Tomcat..."
        sudo wget -q "$TOMCAT_URL" -O "$SOURCES_DIR/$TOMCAT_FILE"
    fi

    sudo tar -xzf "$SOURCES_DIR/$TOMCAT_FILE" -C "$INSTALL_DIR"
    EXTRACTED_DIR=$(tar -tf "$SOURCES_DIR/$TOMCAT_FILE" | head -1 | cut -d/ -f1)
    sudo mv "$INSTALL_DIR/$EXTRACTED_DIR" "$TOMCAT_HOME"

    sudo groupadd -r tomcat 2>/dev/null || true
    sudo useradd -r -g tomcat -d "$TOMCAT_HOME" tomcat 2>/dev/null || true
    sudo chown -R tomcat:tomcat "$TOMCAT_HOME"

    sudo tee /etc/systemd/system/tomcat.service << 'EOF' > /dev/null
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment=JAVA_HOME=/opt/jdk
Environment=CATALINA_HOME=/opt/tomcat
Environment=CATALINA_BASE=/opt/tomcat
ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    log_success "Tomcat installed"
}

# ============================================================================
# 5. Install Jenkins
# ============================================================================
install_jenkins() {
    log_info "Installing Jenkins..."
    JENKINS_WAR="jenkins.war"
    JENKINS_URL="https://get.jenkins.io/war-stable/2.500.0/jenkins.war"

    if [ ! -f "$SOURCES_DIR/$JENKINS_WAR" ]; then
        log_info "Downloading Jenkins..."
        sudo wget -q "$JENKINS_URL" -O "$SOURCES_DIR/$JENKINS_WAR"
    fi

    sudo mkdir -p "$JENKINS_HOME"
    sudo cp "$SOURCES_DIR/$JENKINS_WAR" "$JENKINS_HOME/"

    sudo groupadd -r jenkins 2>/dev/null || true
    sudo useradd -r -g jenkins -d "$JENKINS_HOME" jenkins 2>/dev/null || true
    sudo chown -R jenkins:jenkins "$JENKINS_HOME"

    sudo tee /etc/systemd/system/jenkins.service << 'EOF' > /dev/null
[Unit]
Description=Jenkins Continuous Integration Server
After=network.target

[Service]
User=jenkins
Group=jenkins
Environment=JAVA_HOME=/opt/jdk
Environment=JENKINS_HOME=/opt/jenkins
ExecStart=/opt/jdk/bin/java -jar /opt/jenkins/jenkins.war --httpPort=8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    log_success "Jenkins installed"
}

# ============================================================================
# 6. Install Docker
# ============================================================================
install_docker() {
    log_info "Installing Docker..."
    DOCKER_FILE="docker-28.3.3.tgz"
    DOCKER_URL="https://download.docker.com/linux/static/stable/x86_64/${DOCKER_FILE}"

    if [ ! -f "$SOURCES_DIR/$DOCKER_FILE" ]; then
        log_info "Downloading Docker..."
        sudo wget -q "$DOCKER_URL" -O "$SOURCES_DIR/$DOCKER_FILE"
    fi

    sudo tar -xzf "$SOURCES_DIR/$DOCKER_FILE" -C "$INSTALL_DIR"
    sudo mv "$INSTALL_DIR/docker" "$DOCKER_HOME"

    sudo ln -sf "$DOCKER_HOME/docker" /usr/local/bin/docker
    sudo ln -sf "$DOCKER_HOME/dockerd" /usr/local/bin/dockerd

    sudo groupadd -r docker 2>/dev/null || true
    log_success "Docker installed"
}

# ============================================================================
# 7. Install kubectl
# ============================================================================
install_kubectl() {
    log_info "Installing kubectl..."
    KUBECTL_URL="https://dl.k8s.io/release/v1.32.4/bin/linux/amd64/kubectl"

    if [ ! -f "$SOURCES_DIR/kubectl" ]; then
        log_info "Downloading kubectl..."
        sudo wget -q "$KUBECTL_URL" -O "$SOURCES_DIR/kubectl"
    fi

    sudo install -m 755 "$SOURCES_DIR/kubectl" /usr/local/bin/kubectl
    log_success "kubectl installed"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    log_info "=== Java Development Environment Installation ==="

    install_java
    install_maven
    install_gradle
    install_tomcat
    install_jenkins
    install_docker
    install_kubectl

    log_success "All Java development tools installed."
    echo ""
    echo "Summary of installed components:"
    echo "  - OpenJDK 21 (Temurin)   : $JAVA_HOME"
    echo "  - Apache Maven           : $MAVEN_HOME"
    echo "  - Gradle                 : $GRADLE_HOME"
    echo "  - Apache Tomcat          : $TOMCAT_HOME"
    echo "  - Jenkins                : $JENKINS_HOME"
    echo "  - Docker                 : $DOCKER_HOME"
    echo "  - kubectl                : /usr/local/bin/kubectl"
    echo ""
    echo "To enable services:"
    echo "  sudo systemctl enable tomcat"
    echo "  sudo systemctl enable jenkins"
    echo "  # (Docker daemon is not auto-started; use 'dockerd' manually or set up a service)"
    echo ""
    echo "Environment variables are set in /etc/profile.d/ (java.sh, maven.sh, gradle.sh)"
    echo "Source them or log out/in to apply."
}

main "$@"