#!/bin/bash
# Profile Java Development pour LFS

set -e

log_info() { echo -e "\033[0;32m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;34m[SUCCESS]\033[0m $1"; }

# Variables
JAVA_HOME="/opt/jdk-21.0.2"
MAVEN_HOME="/opt/maven"
GRADLE_HOME="/opt/gradle"
TOMCAT_HOME="/opt/tomcat"
NODE_HOME="/opt/node"

# Installation
install_java_dev() {
    log_info "Installation du profile Java Development"

    # Exécuter le script d'installation
    if [ -f "/sources/12-install-java-dev.sh" ]; then
        bash /sources/12-install-java-dev.sh
    else
        log_error "Script d'installation Java non trouvé"
        exit 1
    fi

    # Configuration des alias pour l'utilisateur lfsuser
    cat >> /home/lfsuser/.bashrc << 'EOF'

# Java Dev Aliases
alias java-build='mvn clean compile'
alias java-test='mvn test'
alias java-package='mvn package'
alias java-run='mvn exec:java'
alias gradle-build='./gradlew build'
alias gradle-test='./gradlew test'
alias tomcat-start='systemctl start tomcat'
alias tomcat-stop='systemctl stop tomcat'
alias tomcat-status='systemctl status tomcat'

# Quick navigation
alias proj='cd ~/projects'
EOF

    # Création du répertoire projets
    mkdir -p /home/lfsuser/projects
    chown -R lfsuser:lfsuser /home/lfsuser/projects

    log_success "Profile Java Development installé"
}

# Création d'exemples de projets
create_demo_projects() {
    log_info "Création de projets de démonstration..."

    # Spring Boot demo
    cat > /home/lfsuser/projects/DemoApplication.java << 'EOF'
import org.springframework.boot.*;
import org.springframework.boot.autoconfigure.*;
import org.springframework.web.bind.annotation.*;

@RestController
@SpringBootApplication
public class DemoApplication {

    @GetMapping("/")
    String home() {
        return "Hello LFS Java World!";
    }

    public static void main(String[] args) {
        SpringApplication.run(DemoApplication.class, args);
    }
}
EOF

    # Build script
    cat > /home/lfsuser/projects/build.gradle << 'EOF'
plugins {
    id 'java'
    id 'org.springframework.boot' version '3.2.0'
    id 'io.spring.dependency-management' version '1.1.4'
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
    implementation 'org.springframework.boot:spring-boot-starter-web'
    testImplementation 'org.springframework.boot:spring-boot-starter-test'
}

tasks.named('test') {
    useJUnitPlatform()
}
EOF

    chown -R lfsuser:lfsuser /home/lfsuser/projects

    log_success "Projets de démonstration créés"
}

# Main
main() {
    install_java_dev
    create_demo_projects
    log_success "Profile Java Development prêt à l'emploi"
}

main