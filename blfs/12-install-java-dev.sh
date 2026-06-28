#!/bin/bash
# blfs/12-install-java-dev.sh
# Java Development Tools Installation for LFS/BLFS (sysvinit compatible)

set -e

log_info()  { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success(){ echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_error()  { echo -e "\033[0;31m[ERROR]\033[0m $1"; }

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

    # Extract with sudo
    sudo tar -xzf "$SOURCES_DIR/$JDK_FILE" -C "$INSTALL_DIR"
    # Find the extracted directory name
    EXTRACTED_DIR=$(sudo tar -tf "$SOURCES_DIR/$JDK_FILE" | head -1 | cut -d/ -f1)
    log_info "Extracted directory: $EXTRACTED_DIR"
    sudo mv "$INSTALL_DIR/$EXTRACTED_DIR" "$JAVA_HOME"

    # Verify installation
    if [ ! -f "$JAVA_HOME/bin/java" ]; then
        log_error "Java binary not found at $JAVA_HOME/bin/java"
        exit 1
    fi

    # Set environment variables
    sudo tee /etc/profile.d/java.sh << 'EOF' > /dev/null
export JAVA_HOME=/opt/jdk
export PATH=$JAVA_HOME/bin:$PATH
EOF
    sudo chmod +x /etc/profile.d/java.sh
    # Source for current shell
    source /etc/profile.d/java.sh

    log_success "Java installed: $($JAVA_HOME/bin/java -version 2>&1 | head -n1)"
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
    EXTRACTED_DIR=$(sudo tar -tf "$SOURCES_DIR/$MVN_FILE" | head -1 | cut -d/ -f1)
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
# 4. Install Apache Tomcat (sysvinit compatible)
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
    EXTRACTED_DIR=$(sudo tar -tf "$SOURCES_DIR/$TOMCAT_FILE" | head -1 | cut -d/ -f1)
    sudo mv "$INSTALL_DIR/$EXTRACTED_DIR" "$TOMCAT_HOME"

    sudo groupadd -r tomcat 2>/dev/null || true
    sudo useradd -r -g tomcat -d "$TOMCAT_HOME" tomcat 2>/dev/null || true
    sudo chown -R tomcat:tomcat "$TOMCAT_HOME"

    # Créer un script de démarrage sysvinit (au lieu de systemd)
    sudo tee /etc/init.d/tomcat << 'EOF' > /dev/null
#!/bin/sh
### BEGIN INIT INFO
# Provides:          tomcat
# Required-Start:    $network $remote_fs
# Required-Stop:     $network $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Apache Tomcat
### END INIT INFO

export JAVA_HOME=/opt/jdk
export CATALINA_HOME=/opt/tomcat
export CATALINA_BASE=/opt/tomcat

case "$1" in
    start)
        $CATALINA_HOME/bin/startup.sh
        ;;
    stop)
        $CATALINA_HOME/bin/shutdown.sh
        ;;
    restart)
        $CATALINA_HOME/bin/shutdown.sh
        $CATALINA_HOME/bin/startup.sh
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
EOF
    sudo chmod +x /etc/init.d/tomcat

    log_success "Tomcat installed (sysvinit script available)"
}

# ============================================================================
# 5. Install Jenkins (sysvinit compatible)
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

    # Script de démarrage sysvinit
    sudo tee /etc/init.d/jenkins << 'EOF' > /dev/null
#!/bin/sh
### BEGIN INIT INFO
# Provides:          jenkins
# Required-Start:    $network $remote_fs
# Required-Stop:     $network $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Jenkins CI Server
### END INIT INFO

export JAVA_HOME=/opt/jdk
export JENKINS_HOME=/opt/jenkins

case "$1" in
    start)
        su - jenkins -c "nohup $JAVA_HOME/bin/java -jar $JENKINS_HOME/jenkins.war --httpPort=8080 > /var/log/jenkins.log 2>&1 &"
        ;;
    stop)
        pkill -f "jenkins.war" || true
        ;;
    restart)
        pkill -f "jenkins.war" || true
        su - jenkins -c "nohup $JAVA_HOME/bin/java -jar $JENKINS_HOME/jenkins.war --httpPort=8080 > /var/log/jenkins.log 2>&1 &"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
        exit 1
        ;;
esac
EOF
    sudo chmod +x /etc/init.d/jenkins

    log_success "Jenkins installed (sysvinit script available)"
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

    # Supprimer l'ancienne installation
    sudo rm -rf "$DOCKER_HOME"

    # Extraire directement dans /opt (cela crée /opt/docker)
    sudo tar -xzf "$SOURCES_DIR/$DOCKER_FILE" -C "$INSTALL_DIR"

    # Créer les liens symboliques
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
    echo "To enable Tomcat and Jenkins at boot (sysvinit):"
    echo "  sudo update-rc.d tomcat defaults"
    echo "  sudo update-rc.d jenkins defaults"
    echo ""
    echo "To start manually:"
    echo "  sudo /etc/init.d/tomcat start"
    echo "  sudo /etc/init.d/jenkins start"
    echo ""
    echo "Environment variables are set in /etc/profile.d/ (java.sh, maven.sh, gradle.sh)"
    echo "Source them or log out/in to apply."
}

main "$@"