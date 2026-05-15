#!/bin/bash
# Java Development Environment Installation for LFS
# Run inside chroot environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_success() { echo -e "${BLUE}[SUCCESS]${NC} $1"; }

# Configuration
JAVA_VERSION="21.0.2"
JAVA_HOME="/opt/jdk-${JAVA_VERSION}"
MAVEN_VERSION="3.9.6"
GRADLE_VERSION="8.5"
TOMCAT_VERSION="10.1.16"
NODE_VERSION="20.11.0"
DOCKER_VERSION="24.0.7"
KUBECTL_VERSION="1.29.0"
JENKINS_VERSION="2.440"

# Create directories
mkdir -p /opt /usr/local/bin /etc/profile.d

###############################################################################
# 1. INSTALL JAVA (OpenJDK)
###############################################################################
install_java() {
    log_info "Installing Java ${JAVA_VERSION}..."

    cd /sources

    if [ ! -f "openjdk-${JAVA_VERSION}_linux-x64_bin.tar.gz" ]; then
        wget https://download.java.net/java/GA/jdk${JAVA_VERSION}/6c0d5c0c4b1f4f9c8e9c8d7e6f5e4d3c/${JAVA_VERSION}/GPL/openjdk-${JAVA_VERSION}_linux-x64_bin.tar.gz
    fi

    tar -xzf openjdk-${JAVA_VERSION}_linux-x64_bin.tar.gz -C /opt
    mv /opt/jdk-${JAVA_VERSION} /opt/jdk-${JAVA_VERSION}

    cat > /etc/profile.d/java.sh << EOF
export JAVA_HOME=/opt/jdk-${JAVA_VERSION}
export PATH=\$JAVA_HOME/bin:\$PATH
export CLASSPATH=.:\$JAVA_HOME/lib/dt.jar:\$JAVA_HOME/lib/tools.jar
EOF

    chmod +x /etc/profile.d/java.sh
    source /etc/profile.d/java.sh

    if java -version 2>&1 | grep -q "version"; then
        log_success "Java installed successfully"
    else
        log_error "Java installation failed"
        return 1
    fi
}

###############################################################################
# 2. INSTALL MAVEN
###############################################################################
install_maven() {
    log_info "Installing Maven ${MAVEN_VERSION}..."

    cd /sources
    wget https://dlcdn.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz
    tar -xzf apache-maven-${MAVEN_VERSION}-bin.tar.gz -C /opt
    ln -sf /opt/apache-maven-${MAVEN_VERSION} /opt/maven

    cat > /etc/profile.d/maven.sh << EOF
export MAVEN_HOME=/opt/maven
export PATH=\$MAVEN_HOME/bin:\$PATH
EOF

    chmod +x /etc/profile.d/maven.sh

    log_success "Maven installed"
}

###############################################################################
# 3. INSTALL GRADLE
###############################################################################
install_gradle() {
    log_info "Installing Gradle ${GRADLE_VERSION}..."

    cd /sources
    wget https://services.gradle.org/distributions/gradle-${GRADLE_VERSION}-bin.zip
    unzip gradle-${GRADLE_VERSION}-bin.zip -d /opt
    ln -sf /opt/gradle-${GRADLE_VERSION} /opt/gradle

    cat > /etc/profile.d/gradle.sh << EOF
export GRADLE_HOME=/opt/gradle
export PATH=\$GRADLE_HOME/bin:\$PATH
EOF

    chmod +x /etc/profile.d/gradle.sh

    log_success "Gradle installed"
}

###############################################################################
# 4. INSTALL TOMCAT
###############################################################################
install_tomcat() {
    log_info "Installing Tomcat ${TOMCAT_VERSION}..."

    groupadd -r tomcat 2>/dev/null || true
    useradd -r -g tomcat -d /opt/tomcat -s /bin/false tomcat 2>/dev/null || true

    cd /sources
    wget https://dlcdn.apache.org/tomcat/tomcat-10/v${TOMCAT_VERSION}/bin/apache-tomcat-${TOMCAT_VERSION}.tar.gz
    tar -xzf apache-tomcat-${TOMCAT_VERSION}.tar.gz -C /opt
    ln -sf /opt/apache-tomcat-${TOMCAT_VERSION} /opt/tomcat

    chown -R tomcat:tomcat /opt/tomcat
    chmod +x /opt/tomcat/bin/*.sh

    cat > /etc/systemd/system/tomcat.service << EOF
[Unit]
Description=Apache Tomcat Web Application Container
After=network.target

[Service]
Type=forking
User=tomcat
Group=tomcat
Environment=JAVA_HOME=/opt/jdk-${JAVA_VERSION}
Environment=CATALINA_PID=/opt/tomcat/temp/tomcat.pid
Environment=CATALINA_HOME=/opt/tomcat
Environment=CATALINA_BASE=/opt/tomcat
ExecStart=/opt/tomcat/bin/startup.sh
ExecStop=/opt/tomcat/bin/shutdown.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable tomcat

    log_success "Tomcat installed"
}

###############################################################################
# 5. INSTALL NODE.JS
###############################################################################
install_nodejs() {
    log_info "Installing Node.js ${NODE_VERSION}..."

    cd /sources
    wget https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz
    tar -xJf node-v${NODE_VERSION}-linux-x64.tar.xz -C /opt
    ln -sf /opt/node-v${NODE_VERSION}-linux-x64 /opt/node

    cat > /etc/profile.d/node.sh << EOF
export NODE_HOME=/opt/node
export PATH=\$NODE_HOME/bin:\$PATH
EOF

    chmod +x /etc/profile.d/node.sh
    source /etc/profile.d/node.sh

    npm install -g npm@latest
    npm install -g yarn pnpm typescript ts-node nodemon eslint prettier

    log_success "Node.js installed"
}

###############################################################################
# 6. INSTALL DOCKER (static binary for LFS)
###############################################################################
install_docker() {
    log_info "Installing Docker ${DOCKER_VERSION}..."

    cd /sources
    wget https://download.docker.com/linux/static/stable/x86_64/docker-${DOCKER_VERSION}.tgz
    tar -xzf docker-${DOCKER_VERSION}.tgz -C /opt

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

    log_success "Docker installed"
}

###############################################################################
# 7. INSTALL KUBECTL
###############################################################################
install_kubectl() {
    log_info "Installing kubectl ${KUBECTL_VERSION}..."

    cd /sources
    wget https://dl.k8s.io/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl
    chmod +x kubectl
    mv kubectl /usr/local/bin/

    log_success "kubectl installed"
}

###############################################################################
# 8. INSTALL JENKINS
###############################################################################
install_jenkins() {
    log_info "Installing Jenkins ${JENKINS_VERSION}..."

    groupadd -r jenkins 2>/dev/null || true
    useradd -r -g jenkins -d /var/lib/jenkins -s /bin/false jenkins 2>/dev/null || true

    mkdir -p /var/lib/jenkins /var/log/jenkins /var/cache/jenkins
    chown -R jenkins:jenkins /var/lib/jenkins /var/log/jenkins /var/cache/jenkins

    cd /sources
    wget https://get.jenkins.io/war/${JENKINS_VERSION}/jenkins.war

    mkdir -p /opt/jenkins
    mv jenkins.war /opt/jenkins/

    cat > /etc/systemd/system/jenkins.service << EOF
[Unit]
Description=Jenkins Continuous Integration Server
After=network.target

[Service]
User=jenkins
Group=jenkins
Environment=JAVA_HOME=/opt/jdk-${JAVA_VERSION}
Environment=JENKINS_HOME=/var/lib/jenkins
ExecStart=/opt/jdk-${JAVA_VERSION}/bin/java -jar /opt/jenkins/jenkins.war --httpPort=8080
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable jenkins

    log_success "Jenkins installed"
}

###############################################################################
# 9. INSTALL TESTING TOOLS
###############################################################################
install_testing_tools() {
    log_info "Installing testing tools..."

    cd /sources

    # Apache JMeter
    wget https://dlcdn.apache.org/jmeter/binaries/apache-jmeter-5.6.3.tgz
    tar -xzf apache-jmeter-5.6.3.tgz -C /opt
    ln -sf /opt/apache-jmeter-5.6.3 /opt/jmeter

    # Allure
    wget https://github.com/allure-framework/allure2/releases/download/2.25.0/allure-2.25.0.tgz
    tar -xzf allure-2.25.0.tgz -C /opt
    ln -sf /opt/allure-2.25.0 /opt/allure

    cat > /etc/profile.d/test-tools.sh << EOF
export JMETER_HOME=/opt/jmeter
export ALLURE_HOME=/opt/allure
export PATH=\$JMETER_HOME/bin:\$ALLURE_HOME/bin:\$PATH
EOF

    log_success "Testing tools installed"
}

###############################################################################
# 10. CONFIGURE DEV ENVIRONMENT
###############################################################################
configure_dev_environment() {
    log_info "Configuring development environment..."

    cat > /etc/profile.d/java-dev.sh << 'EOF'
# Java Development Environment
export JAVA_HOME=/opt/jdk-21.0.2
export MAVEN_HOME=/opt/maven
export GRADLE_HOME=/opt/gradle
export NODE_HOME=/opt/node
export TOMCAT_HOME=/opt/tomcat
export JMETER_HOME=/opt/jmeter
export ALLURE_HOME=/opt/allure

export PATH=$JAVA_HOME/bin:$MAVEN_HOME/bin:$GRADLE_HOME/bin:$NODE_HOME/bin:$JMETER_HOME/bin:$ALLURE_HOME/bin:$PATH
export CLASSPATH=.:$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar

# Maven options
export MAVEN_OPTS="-Xms512m -Xmx2048m -XX:MetaspaceSize=256m"

# Gradle options
export GRADLE_OPTS="-Dorg.gradle.daemon=true -Dorg.gradle.parallel=true -Dorg.gradle.caching=true"

# Java options
export JAVA_OPTS="-Xms512m -Xmx2048m -XX:+UseG1GC -XX:+UseStringDeduplication"

# Node options
export NODE_OPTIONS="--max-old-space-size=2048"
EOF

    chmod +x /etc/profile.d/java-dev.sh

    # Maven settings
    mkdir -p /etc/maven
    cat > /etc/maven/settings.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<settings xmlns="http://maven.apache.org/SETTINGS/1.0.0"
          xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
          xsi:schemaLocation="http://maven.apache.org/SETTINGS/1.0.0 http://maven.apache.org/xsd/settings-1.0.0.xsd">

    <localRepository>/opt/maven/repository</localRepository>

    <mirrors>
        <mirror>
            <id>central</id>
            <url>https://repo.maven.apache.org/maven2</url>
            <mirrorOf>central</mirrorOf>
        </mirror>
    </mirrors>

    <profiles>
        <profile>
            <id>jdk-21</id>
            <activation>
                <activeByDefault>true</activeByDefault>
                <jdk>21</jdk>
            </activation>
            <properties>
                <maven.compiler.source>21</maven.compiler.source>
                <maven.compiler.target>21</maven.compiler.target>
                <maven.compiler.release>21</maven.compiler.release>
            </properties>
        </profile>
    </profiles>
</settings>
EOF

    # Gradle init script
    mkdir -p /opt/gradle/init.d
    cat > /opt/gradle/init.d/repositories.gradle << 'EOF'
allprojects {
    repositories {
        mavenLocal()
        mavenCentral()
        google()
    }

    tasks.withType(JavaCompile) {
        options.encoding = 'UTF-8'
        options.compilerArgs += ['-Xlint:unchecked', '-Xlint:deprecation']
    }
}
EOF

    log_success "Development environment configured"
}

###############################################################################
# 11. SYSTEM OPTIMIZATIONS
###############################################################################
optimize_system() {
    log_info "Optimizing system for Java development..."

    cat > /etc/sysctl.d/99-java.conf << EOF
# Java optimizations
vm.max_map_count = 262144
fs.file-max = 65535
kernel.threads-max = 65536
kernel.pid_max = 65536
net.core.somaxconn = 65535
EOF

    cat > /etc/security/limits.d/99-java.conf << EOF
* soft nofile 65535
* hard nofile 65535
* soft nproc 32768
* hard nproc 32768
* soft memlock unlimited
* hard memlock unlimited
EOF

    if [ ! -f /swapfile ]; then
        log_info "Creating 4GB swapfile for Java..."
        dd if=/dev/zero of=/swapfile bs=1M count=4096
        chmod 600 /swapfile
        mkswap /swapfile
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
        swapon /swapfile
    fi

    log_success "System optimizations applied"
}

###############################################################################
# 12. UTILITY SCRIPTS
###############################################################################
install_utilities() {
    log_info "Installing utility scripts..."

    cat > /usr/local/bin/new-java-project << 'EOF'
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: new-java-project <project-name>"
    exit 1
fi

mvn archetype:generate \
    -DgroupId=com.example \
    -DartifactId=$1 \
    -DarchetypeArtifactId=maven-archetype-quickstart \
    -DinteractiveMode=false

cd $1
echo "Project $1 created successfully"
EOF
    chmod +x /usr/local/bin/new-java-project

    cat > /usr/local/bin/new-spring-project << 'EOF'
#!/bin/bash
if [ -z "$1" ]; then
    echo "Usage: new-spring-project <project-name>"
    exit 1
fi

curl https://start.spring.io/starter.zip \
    -d dependencies=web,lombok,devtools \
    -d name=$1 \
    -d groupId=com.example \
    -d artifactId=$1 \
    -d javaVersion=21 \
    -o $1.zip

unzip $1.zip -d $1
rm $1.zip
cd $1
echo "Spring Boot project $1 created successfully"
EOF
    chmod +x /usr/local/bin/new-spring-project

    cat > /usr/local/bin/parallel-build << 'EOF'
#!/bin/bash
if [ -f "pom.xml" ]; then
    mvn clean install -T 1C -DskipTests
elif [ -f "build.gradle" ]; then
    ./gradlew clean build --parallel --max-workers=$(nproc)
else
    echo "No Maven/Gradle project found"
fi
EOF
    chmod +x /usr/local/bin/parallel-build

    # Bash aliases for lfsuser
    mkdir -p /home/lfsuser
    cat >> /home/lfsuser/.bashrc << 'EOF' 2>/dev/null || true

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
alias jenkins-start='systemctl start jenkins'
alias jenkins-stop='systemctl stop jenkins'
alias docker-clean='docker system prune -af'

# Quick navigation
alias proj='cd ~/projects'
EOF

    mkdir -p /home/lfsuser/projects
    chown -R lfsuser:lfsuser /home/lfsuser 2>/dev/null || true

    log_success "Utility scripts installed"
}

###############################################################################
# 13. DEMO PROJECTS
###############################################################################
create_demo_projects() {
    log_info "Creating demo projects..."

    mkdir -p /home/lfsuser/projects

    # Simple Java demo
    cat > /home/lfsuser/projects/HelloWorld.java << 'EOF'
public class HelloWorld {
    public static void main(String[] args) {
        System.out.println("Hello from LFS Java Development Environment!");
        System.out.println("Java version: " + System.getProperty("java.version"));
        System.out.println("OS: " + System.getProperty("os.name"));
    }
}
EOF

    # Gradle build file
    cat > /home/lfsuser/projects/build.gradle << 'EOF'
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
    implementation 'com.google.guava:guava:32.1.3-jre'
    testImplementation 'org.junit.jupiter:junit-jupiter:5.10.1'
}

application {
    mainClass = 'HelloWorld'
}

test {
    useJUnitPlatform()
}
EOF

    chown -R lfsuser:lfsuser /home/lfsuser/projects

    log_success "Demo projects created"
}

###############################################################################
# MAIN
###############################################################################
main() {
    log_info "=== JAVA DEVELOPMENT ENVIRONMENT INSTALLATION ==="

    install_java || exit 1
    install_maven
    install_gradle
    install_tomcat
    install_nodejs
    install_docker
    install_kubectl
    install_jenkins
    install_testing_tools
    configure_dev_environment
    optimize_system
    install_utilities
    create_demo_projects

    log_success "=== INSTALLATION COMPLETE ==="

    echo ""
    echo "Java Development Environment installed successfully!"
    echo ""
    echo "Installed versions:"
    java -version 2>&1 | head -n1
    mvn -version 2>&1 | head -n1
    gradle -version 2>&1 | grep Gradle
    node --version
    docker --version 2>&1 || echo "Docker installed"
    echo ""
    echo "To activate environment: source /etc/profile.d/java-dev.sh"
    echo ""
    echo "Services available:"
    echo "  systemctl start|stop|restart tomcat"
    echo "  systemctl start|stop|restart docker"
    echo "  systemctl start|stop|restart jenkins"
    echo ""
    echo "Quick commands:"
    echo "  new-java-project <name>"
    echo "  new-spring-project <name>"
    echo "  parallel-build"
}

main "$@"