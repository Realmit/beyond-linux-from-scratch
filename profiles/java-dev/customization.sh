#!/bin/bash
# Java Development Profile for LFS
# Complete Java development environment setup

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_error() { echo -e "\033[0;31m[ERROR]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }
log_warning() { echo -e "\033[1;33m[WARNING]\033[0m $1"; }

# ============================================================================
# CONFIGURATION
# ============================================================================

JAVA_VERSION="21.0.8"
MAVEN_VERSION="3.9.9"
GRADLE_VERSION="8.13"
TOMCAT_VERSION="10.1.39"
NODE_VERSION="22.14.0"
DOCKER_VERSION="27.4.1"
JENKINS_VERSION="2.492.2"

JAVA_HOME="/opt/jdk-${JAVA_VERSION}"
MAVEN_HOME="/opt/maven"
GRADLE_HOME="/opt/gradle"
TOMCAT_HOME="/opt/tomcat"
NODE_HOME="/opt/node"

PACKAGE_LIST="profiles/java-dev/packages.list"
NUM_JOBS=${NUM_JOBS:-$(nproc)}

# ============================================================================
# INSTALL JAVA
# ============================================================================
install_java() {
    log_info "Installing OpenJDK ${JAVA_VERSION}..."

    cd /sources

    # Download from Eclipse Temurin (Adoptium)
    JDK_URL="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-${JAVA_VERSION}%2B9/OpenJDK21U-jdk_x64_linux_hotspot_${JAVA_VERSION}_9.tar.gz"
    JDK_FILE="OpenJDK21U-jdk_x64_linux_hotspot_${JAVA_VERSION}_9.tar.gz"

    if [ ! -f "$JDK_FILE" ]; then
        wget "$JDK_URL" -O "$JDK_FILE"
    fi

    # Extract and install
    tar -xzf "$JDK_FILE" -C /opt
    mv /opt/jdk-${JAVA_VERSION}* "$JAVA_HOME" 2>/dev/null || true

    # Set environment variables
    cat > /etc/profile.d/java.sh << EOF
export JAVA_HOME=${JAVA_HOME}
export PATH=\$JAVA_HOME/bin:\$PATH
export CLASSPATH=.:\$JAVA_HOME/lib/dt.jar:\$JAVA_HOME/lib/tools.jar
EOF

    chmod +x /etc/profile.d/java.sh
    source /etc/profile.d/java.sh

    # Verify installation
    if ${JAVA_HOME}/bin/java -version 2>&1 | grep -q "version"; then
        log_success "Java ${JAVA_VERSION} installed successfully"
    else
        log_error "Java installation failed"
        return 1
    fi
}

# ============================================================================
# INSTALL MAVEN
# ============================================================================
install_maven() {
    log_info "Installing Maven ${MAVEN_VERSION}..."

    cd /sources

    MAVEN_URL="https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
    MAVEN_FILE="apache-maven-${MAVEN_VERSION}-bin.tar.gz"

    if [ ! -f "$MAVEN_FILE" ]; then
        wget "$MAVEN_URL"
    fi

    tar -xzf "$MAVEN_FILE" -C /opt
    ln -sf "/opt/apache-maven-${MAVEN_VERSION}" "$MAVEN_HOME"

    cat > /etc/profile.d/maven.sh << EOF
export MAVEN_HOME=/opt/maven
export PATH=\$MAVEN_HOME/bin:\$PATH
EOF

    chmod +x /etc/profile.d/maven.sh

    # Create local repository
    mkdir -p /opt/maven/repository
    chmod -R 777 /opt/maven/repository

    log_success "Maven ${MAVEN_VERSION} installed"
}

# ============================================================================
# INSTALL GRADLE
# ============================================================================
install_gradle() {
    log_info "Installing Gradle ${GRADLE_VERSION}..."

    cd /sources

    GRADLE_URL="https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip"
    GRADLE_FILE="gradle-${GRADLE_VERSION}-bin.zip"

    if [ ! -f "$GRADLE_FILE" ]; then
        wget "$GRADLE_URL"
    fi

    unzip -q "$GRADLE_FILE" -d /opt
    ln -sf "/opt/gradle-${GRADLE_VERSION}" "$GRADLE_HOME"

    cat > /etc/profile.d/gradle.sh << EOF
export GRADLE_HOME=/opt/gradle
export PATH=\$GRADLE_HOME/bin:\$PATH
EOF

    chmod +x /etc/profile.d/gradle.sh

    log_success "Gradle ${GRADLE_VERSION} installed"
}

# ============================================================================
# INSTALL TOMCAT
# ============================================================================
install_tomcat() {
    log_info "Installing Apache Tomcat ${TOMCAT_VERSION}..."

    # Create tomcat user
    groupadd -r tomcat 2>/dev/null || true
    useradd -r -g tomcat -d "$TOMCAT_HOME" -s /bin/false tomcat 2>/dev/null || true

    cd /sources

    TOMCAT_URL="https://dlcdn.apache.org/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz"
    TOMCAT_FILE="apache-tomcat-${TOMCAT_VERSION}.tar.gz"

    if [ ! -f "$TOMCAT_FILE" ]; then
        wget "$TOMCAT_URL"
    fi

    tar -xzf "$TOMCAT_FILE" -C /opt
    ln -sf "/opt/apache-tomcat-${TOMCAT_VERSION}" "$TOMCAT_HOME"

    # Set permissions
    chown -R tomcat:tomcat "$TOMCAT_HOME"
    chmod +x "$TOMCAT_HOME"/bin/*.sh

    # Create systemd service
    cat > /etc/systemd/system/tomcat.service << EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment=JAVA_HOME=${JAVA_HOME}
Environment=CATALINA_PID=${TOMCAT_HOME}/temp/tomcat.pid
Environment=CATALINA_HOME=${TOMCAT_HOME}
Environment=CATALINA_BASE=${TOMCAT_HOME}
ExecStart=${TOMCAT_HOME}/bin/startup.sh
ExecStop=${TOMCAT_HOME}/bin/shutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable tomcat

    log_success "Tomcat ${TOMCAT_VERSION} installed"
}

# ============================================================================
# INSTALL NODE.JS
# ============================================================================
install_nodejs() {
    log_info "Installing Node.js ${NODE_VERSION}..."

    cd /sources

    NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz"
    NODE_FILE="node-v${NODE_VERSION}-linux-x64.tar.xz"

    if [ ! -f "$NODE_FILE" ]; then
        wget "$NODE_URL"
    fi

    tar -xJf "$NODE_FILE" -C /opt
    ln -sf "/opt/node-v${NODE_VERSION}-linux-x64" "$NODE_HOME"

    cat > /etc/profile.d/node.sh << EOF
export NODE_HOME=/opt/node
export PATH=\$NODE_HOME/bin:\$PATH
EOF

    chmod +x /etc/profile.d/node.sh
    source /etc/profile.d/node.sh

    # Install global npm packages
    npm install -g npm@latest
    npm install -g yarn pnpm typescript ts-node nodemon \
        @angular/cli @vue/cli create-react-app \
        pm2 forever nodemon

    log_success "Node.js ${NODE_VERSION} installed"
}

# ============================================================================
# INSTALL DOCKER
# ============================================================================
install_docker() {
    log_info "Installing Docker ${DOCKER_VERSION}..."

    cd /sources

    DOCKER_URL="https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz"
    DOCKER_FILE="docker-${DOCKER_VERSION}.tgz"

    if [ ! -f "$DOCKER_FILE" ]; then
        wget "$DOCKER_URL"
    fi

    tar -xzf "$DOCKER_FILE" -C /opt

    ln -sf /opt/docker/docker /usr/local/bin/docker
    ln -sf /opt/docker/dockerd /usr/local/bin/dockerd

    groupadd -r docker 2>/dev/null || true

    cat > /etc/systemd/system/docker.service << EOF
[Unit]
Description=Docker Application Container Engine
After=network.target

[Service]
Type=notify
ExecStart=/usr/local/bin/dockerd
ExecReload=/bin/kill -s HUP \$MAINPID
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable docker

    log_success "Docker ${DOCKER_VERSION} installed"
}

# ============================================================================
# INSTALL KUBECTL
# ============================================================================
install_kubectl() {
    log_info "Installing kubectl..."

    KUBECTL_VERSION="1.32.3"
    cd /sources

    wget "https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/

    log_success "kubectl ${KUBECTL_VERSION} installed"
}

# ============================================================================
# INSTALL JENKINS
# ============================================================================
install_jenkins() {
    log_info "Installing Jenkins CI/CD..."

    # Create jenkins user
    groupadd -r jenkins 2>/dev/null || true
    useradd -r -g jenkins -d /var/lib/jenkins -s /bin/false jenkins 2>/dev/null || true

    mkdir -p /var/lib/jenkins /var/log/jenkins /var/cache/jenkins
    chown -R jenkins:jenkins /var/lib/jenkins /var/log/jenkins /var/cache/jenkins

    cd /sources
    wget "https://get.jenkins.io/war/${JENKINS_VERSION}/jenkins.war"

    mkdir -p /opt/jenkins
    mv jenkins.war /opt/jenkins/

    cat > /etc/systemd/system/jenkins.service << EOF
[Unit]
Description=Jenkins Continuous Integration Server
After=network.target

[Service]
User=jenkins
Group=jenkins
Environment=JAVA_HOME=${JAVA_HOME}
Environment=JENKINS_HOME=/var/lib/jenkins
ExecStart=${JAVA_HOME}/bin/java -jar /opt/jenkins/jenkins.war --httpPort=8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable jenkins

    log_success "Jenkins ${JENKINS_VERSION} installed"
}

# ============================================================================
# INSTALL SPRING BOOT CLI
# ============================================================================
install_spring_boot_cli() {
    log_info "Installing Spring Boot CLI..."

    cd /sources

    SPRING_VERSION="3.2.0"
    wget "https://repo.spring.io/release/org/springframework/boot/spring-boot-cli/${SPRING_VERSION}/spring-boot-cli-${SPRING_VERSION}-bin.tar.gz"
    tar -xzf spring-boot-cli-${SPRING_VERSION}-bin.tar.gz -C /opt
    ln -sf /opt/spring-${SPRING_VERSION} /opt/spring-boot-cli

    cat > /etc/profile.d/spring.sh << EOF
export SPRING_HOME=/opt/spring-boot-cli
export PATH=\$SPRING_HOME/bin:\$PATH
EOF

    log_success "Spring Boot CLI installed"
}

# ============================================================================
# CONFIGURE JAVA OPTIMIZATIONS
# ============================================================================
configure_java_optimizations() {
    log_info "Configuring Java optimizations..."

    cat >> /etc/profile.d/java-dev.sh << 'EOF'

# Java optimization flags
export JAVA_OPTS="-server -Xms2g -Xmx4g -XX:+UseG1GC -XX:+UseStringDeduplication -XX:+OptimizeStringConcat"
export MAVEN_OPTS="-Xms512m -Xmx2g -XX:MetaspaceSize=256m -XX:MaxMetaspaceSize=512m"
export GRADLE_OPTS="-Dorg.gradle.daemon=true -Dorg.gradle.parallel=true -Dorg.gradle.caching=true -Xms512m -Xmx2g"

# Enable JVM performance flags
export JAVA_TOOL_OPTIONS="-XX:+PrintCommandLineFlags -XX:+PrintGCDetails -XX:+PrintGCTimeStamps"
EOF

    # Create systemd override for Tomcat
    mkdir -p /etc/systemd/system/tomcat.service.d
    cat > /etc/systemd/system/tomcat.service.d/override.conf << EOF
[Service]
Environment="CATALINA_OPTS=-Xms512m -Xmx2g -XX:+UseG1GC -Djava.security.egd=file:/dev/./urandom"
EOF

    log_success "Java optimizations configured"
}

# ============================================================================
# CREATE DEMO PROJECTS
# ============================================================================
create_demo_projects() {
    log_info "Creating demo projects..."

    mkdir -p /home/lfsuser/projects

    # Spring Boot Maven project
    cat > /home/lfsuser/projects/spring-boot-demo/pom.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>3.2.0</version>
    </parent>

    <groupId>com.lfs</groupId>
    <artifactId>demo</artifactId>
    <version>1.0.0</version>
    <name>LFS Spring Boot Demo</name>

    <properties>
        <java.version>21</java.version>
    </properties>

    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-actuator</artifactId>
        </dependency>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-devtools</artifactId>
            <scope>runtime</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>
EOF

    # Spring Boot application
    mkdir -p /home/lfsuser/projects/spring-boot-demo/src/main/java/com/lfs/demo
    cat > /home/lfsuser/projects/spring-boot-demo/src/main/java/com/lfs/demo/DemoApplication.java << 'EOF'
package com.lfs.demo;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@SpringBootApplication
@RestController
public class DemoApplication {

    public static void main(String[] args) {
        SpringApplication.run(DemoApplication.class, args);
    }

    @GetMapping("/")
    public String home() {
        return "Welcome to LFS Java Development Environment!";
    }

    @GetMapping("/health")
    public String health() {
        return "OK";
    }
}
EOF

    # Dockerfile for the demo
    cat > /home/lfsuser/projects/spring-boot-demo/Dockerfile << 'EOF'
FROM openjdk:21-slim
COPY target/*.jar app.jar
ENTRYPOINT ["java", "-jar", "/app.jar"]
EXPOSE 8080
EOF

    # Gradle example
    cat > /home/lfsuser/projects/gradle-demo/build.gradle << 'EOF'
plugins {
    id 'java'
    id 'application'
}

group = 'com.lfs'
version = '1.0.0'

java {
    sourceCompatibility = '21'
}

repositories {
    mavenCentral()
}

dependencies {
    implementation 'com.google.guava:guava:33.0.0-jre'
    testImplementation 'org.junit.jupiter:junit-jupiter:5.10.1'
}

application {
    mainClass = 'com.lfs.demo.Main'
}

test {
    useJUnitPlatform()
}
EOF

    mkdir -p /home/lfsuser/projects/gradle-demo/src/main/java/com/lfs/demo
    cat > /home/lfsuser/projects/gradle-demo/src/main/java/com/lfs/demo/Main.java << 'EOF'
package com.lfs.demo;

import com.google.common.base.Joiner;
import java.util.List;

public class Main {
    public static void main(String[] args) {
        String result = Joiner.on(", ").join(List.of("Hello", "from", "LFS", "Gradle"));
        System.out.println(result);
        System.out.println("Java version: " + System.getProperty("java.version"));
    }
}
EOF

    chown -R lfsuser:lfsuser /home/lfsuser/projects

    log_success "Demo projects created"
}

# ============================================================================
# CONFIGURE ALIASES AND PROFILE
# ============================================================================
configure_aliases() {
    log_info "Configuring developer aliases..."

    cat >> /home/lfsuser/.bashrc << 'EOF'

# ============================================================================
# Java Development Aliases
# ============================================================================

# Maven aliases
alias mci='mvn clean install'
alias mcp='mvn clean package'
alias mct='mvn clean test'
alias mvn-update='mvn versions:use-latest-versions'

# Gradle aliases
alias gb='./gradlew build'
alias gt='./gradlew test'
alias gr='./gradlew run'
alias gcb='./gradlew clean build'

# Docker aliases
alias d='docker'
alias dc='docker-compose'
alias dps='docker ps'
alias di='docker images'
alias dexec='docker exec -it'

# Kubernetes aliases
alias k='kubectl'
alias kg='kubectl get'
alias kd='kubectl describe'
alias kl='kubectl logs'

# Tomcat aliases
alias tomcat-start='sudo systemctl start tomcat'
alias tomcat-stop='sudo systemctl stop tomcat'
alias tomcat-restart='sudo systemctl restart tomcat'
alias tomcat-status='sudo systemctl status tomcat'

# Jenkins aliases
alias jenkins-start='sudo systemctl start jenkins'
alias jenkins-stop='sudo systemctl stop jenkins'
alias jenkins-restart='sudo systemctl restart jenkins'

# Docker aliases
alias docker-start='sudo systemctl start docker'
alias docker-stop='sudo systemctl stop docker'

# Navigation
alias proj='cd ~/projects'
alias spring='cd ~/projects/spring-boot-demo'
alias gradled='cd ~/projects/gradle-demo'

# Quick commands
alias java-version='java -version'
alias mvn-version='mvn -version'
alias gradle-version='gradle -version'
alias node-version='node --version'
alias docker-version='docker --version'
alias kubectl-version='kubectl version --client'

# Status commands
alias dev-status='echo "Java: $(java -version 2>&1 | head -n1)"; echo "Maven: $(mvn -version 2>&1 | head -n1)"; echo "Docker: $(docker --version)"'
EOF

    # Also add helpful functions
    cat >> /home/lfsuser/.bashrc << 'EOF'

# ============================================================================
# Helper Functions
# ============================================================================

# Create new Maven project
new-maven-project() {
    mvn archetype:generate -DgroupId=com.example -DartifactId=$1 -DarchetypeArtifactId=maven-archetype-quickstart -DinteractiveMode=false
    cd $1
    echo "Maven project $1 created"
}

# Create new Spring Boot project
new-spring-project() {
    spring init --dependencies=web,lombok,devtools --groupId=com.example --artifactId=$1 $1
    cd $1
    echo "Spring Boot project $1 created"
}

# Build and run Java file
javarun() {
    javac $1.java && java $1
}

# Kill Java process by port
killport() {
    fuser -k $1/tcp
}

# Show Java process listing
jps() {
    ps aux | grep java
}

# Find in Maven dependencies
find-mvn-dep() {
    mvn dependency:tree | grep -i $1
}

# Clean Docker
docker-clean() {
    docker system prune -af
}

# Kubernetes port forward
kpf() {
    kubectl port-forward pod/$1 $2:$2
}
EOF

    chown lfsuser:lfsuser /home/lfsuser/.bashrc

    log_success "Aliases configured"
}

# ============================================================================
# CLEANUP
# ============================================================================
cleanup() {
    log_info "Cleaning up..."

    cd /sources
    rm -rf OpenJDK*.tar.gz apache-maven-*.tar.gz gradle-*.zip apache-tomcat-*.tar.gz
    rm -rf node-v*.tar.xz docker-*.tgz jenkins.war spring-boot-cli-*.tar.gz

    log_success "Cleanup complete"
}

# ============================================================================
# MAIN
# ============================================================================
main() {
    log_info "========================================="
    log_info "Java Development Environment Installation"
    log_info "========================================="
    log_warning "This will take 1-2 hours..."
    echo ""

    install_java
    install_maven
    install_gradle
    install_tomcat
    install_nodejs
    install_docker
    install_kubectl
    install_jenkins
    install_spring_boot_cli
    configure_java_optimizations
    create_demo_projects
    configure_aliases
    cleanup

    log_success "========================================="
    log_success "Java Development Environment Complete!"
    log_success "========================================="
    echo ""
    echo "Installed versions:"
    java -version 2>&1 | head -1
    mvn -version 2>&1 | head -1
    gradle -version 2>&1 | head -1
    node --version
    docker --version 2>&1
    kubectl version --client 2>&1 | head -1
    echo ""
    echo "Services running:"
    echo "  Tomcat:  http://localhost:8080"
    echo "  Jenkins: http://localhost:8081"
    echo "  Docker:  systemctl start docker"
    echo ""
    echo "Commands:"
    echo "  new-maven-project <name>   - Create Maven project"
    echo "  new-spring-project <name>  - Create Spring Boot project"
    echo "  dev-status                 - Show development status"
    echo ""
    echo "Demo projects in: ~/projects/"
    echo "========================================="
}

main "$@"