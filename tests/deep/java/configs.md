## Full configuration files

Every file the sections above excerpt, complete. Paths are suggestions; keep the `pq-tls/` directory name so the agent's manifest finds its jars. The agent and the java.security override are for JDK 8 to 21 only; remove them when the JDK reaches 25.0.5 or later.

### Agent build (pq-tls kit)

`pq-tls-agent/src/PqTlsAgent.java`

```java
import java.security.Provider;
import java.security.Security;

// Loaded with -javaagent:<dir>/pq-tls-agent.jar (usually via JAVA_TOOL_OPTIONS).
// Agent jars and their manifest Class-Path are on the SYSTEM class path, so the Bouncy Castle
// providers are visible to the JDK's provider lookup without touching application code.
// BCJSSE goes first so SSLContext.getInstance("TLS") / SSLContext.getDefault() use it; the BC JCA
// provider is added LAST so every other crypto lookup keeps resolving to the JDK providers.
public class PqTlsAgent {
    public static void premain(String args) {
        Provider bc = new org.bouncycastle.jce.provider.BouncyCastleProvider();
        Security.addProvider(bc);
        Security.insertProviderAt(new org.bouncycastle.jsse.provider.BouncyCastleJsseProvider(bc), 1);
        if (System.getProperty("jdk.tls.namedGroups") == null) {
            System.setProperty("jdk.tls.namedGroups", "X25519MLKEM768,x25519,secp256r1,secp384r1");
        }
        System.err.println("pq-tls agent: BCJSSE first, groups=" + System.getProperty("jdk.tls.namedGroups"));
    }
}
```

`pq-tls-agent/MANIFEST.MF` (the jar's manifest; jars are found next to the agent jar)

```text
Premain-Class: PqTlsAgent
Class-Path: bcprov-jdk18on-1.87.jar bctls-jdk18on-1.87.jar bcutil-jdk18on-1.87.jar
```

`pq-tls-agent/build.sh` (Java 8 bytecode, so one jar serves JDK 8 to 21)

```bash
#!/bin/bash
set -euo pipefail
BC=1.87
mkdir -p out/pq-tls
for a in bcprov bctls bcutil; do
  curl -fsSLo out/pq-tls/$a-jdk18on-$BC.jar \
    https://repo1.maven.org/maven2/org/bouncycastle/$a-jdk18on/$BC/$a-jdk18on-$BC.jar
done
# Verify checksums against Maven Central before use (sha256 published as .sha256 is not available for all; compare .sha1 at minimum).
for a in bcprov bctls bcutil; do
  want=$(curl -fsSL https://repo1.maven.org/maven2/org/bouncycastle/$a-jdk18on/$BC/$a-jdk18on-$BC.jar.sha1)
  got=$(sha1sum out/pq-tls/$a-jdk18on-$BC.jar | cut -d' ' -f1)
  [ "$want" = "$got" ] || { echo "checksum mismatch: $a"; exit 1; }
done
javac --release 8 -cp "out/pq-tls/*" -d out/classes src/PqTlsAgent.java
jar cfm out/pq-tls/pq-tls-agent.jar MANIFEST.MF -C out/classes PqTlsAgent.class
ls -l out/pq-tls
```

### Dependencies (pom.xml / build.gradle.kts)

`pom.xml` (excerpt: only the dependencies that matter for PQ; pick the ones your service uses)

```xml
<dependencyManagement>
  <dependencies>
    <dependency>
      <groupId>software.amazon.awssdk</groupId>
      <artifactId>bom</artifactId>
      <version>2.59.1</version>   <!-- CRT client PQ by default from 2.35.11 -->
      <type>pom</type>
      <scope>import</scope>
    </dependency>
  </dependencies>
</dependencyManagement>
<dependencies>
  <!-- Option A: AWS SDK v2 CRT HTTP client (PQ for AWS API calls on any JDK, Linux) -->
  <dependency>
    <groupId>software.amazon.awssdk</groupId>
    <artifactId>aws-crt-client</artifactId>
  </dependency>
  <dependency>
    <groupId>software.amazon.awssdk.crt</groupId>
    <artifactId>aws-crt</artifactId>
    <version>0.50.0</version>   <!-- the version the SDK release pins (awscrt.version) -->
  </dependency>

  <!-- Option B: Netty with BoringSSL (PQ by default in the tested versions) -->
  <dependency>
    <groupId>io.netty</groupId>
    <artifactId>netty-tcnative-boringssl-static</artifactId>
    <version>2.0.85.Final</version>
  </dependency>
  <dependency>
    <groupId>io.netty</groupId>
    <artifactId>netty-tcnative-boringssl-static</artifactId>
    <version>2.0.85.Final</version>
    <classifier>linux-x86_64</classifier>
  </dependency>
  <dependency>
    <groupId>io.netty</groupId>
    <artifactId>netty-tcnative-boringssl-static</artifactId>
    <version>2.0.85.Final</version>
    <classifier>linux-aarch_64</classifier>
  </dependency>

  <!-- Option C: Bouncy Castle on the class path for static provider registration
       (not needed for the agent path: the agent jar brings its own copies) -->
  <dependency>
    <groupId>org.bouncycastle</groupId>
    <artifactId>bctls-jdk18on</artifactId>
    <version>1.87</version>
  </dependency>
  <dependency>
    <groupId>org.bouncycastle</groupId>
    <artifactId>bcprov-jdk18on</artifactId>
    <version>1.87</version>
  </dependency>
  <dependency>
    <groupId>org.bouncycastle</groupId>
    <artifactId>bcutil-jdk18on</artifactId>
    <version>1.87</version>
  </dependency>
</dependencies>
```

`build.gradle.kts` (same choices)

```kotlin
dependencies {
    implementation(platform("software.amazon.awssdk:bom:2.59.1"))
    // Option A: CRT HTTP client
    implementation("software.amazon.awssdk:aws-crt-client")
    implementation("software.amazon.awssdk.crt:aws-crt:0.50.0")
    // Option B: Netty + BoringSSL
    implementation("io.netty:netty-tcnative-boringssl-static:2.0.85.Final")
    runtimeOnly("io.netty:netty-tcnative-boringssl-static:2.0.85.Final:linux-x86_64")
    runtimeOnly("io.netty:netty-tcnative-boringssl-static:2.0.85.Final:linux-aarch_64")
    // Option C: Bouncy Castle for static provider registration
    implementation("org.bouncycastle:bctls-jdk18on:1.87")
    implementation("org.bouncycastle:bcprov-jdk18on:1.87")
    implementation("org.bouncycastle:bcutil-jdk18on:1.87")
}
```

### java.security override (static registration, containers and EC2; not Lambda)

`pq-tls/bc-static.security` (JDK 11, 17, 21; load with `-Djava.security.properties=<path>`)

```properties
# Appended to $JAVA_HOME/conf/security/java.security. Bouncy Castle JSSE goes before SunJSSE;
# the BC JCA provider goes last so other crypto keeps resolving to the JDK providers.
# The three BC jars must be on the application class path.
security.provider.1=SUN
security.provider.2=SunRsaSign
security.provider.3=SunEC
security.provider.4=org.bouncycastle.jsse.provider.BouncyCastleJsseProvider BC
security.provider.5=SunJSSE
security.provider.6=SunJCE
security.provider.7=SunJGSS
security.provider.8=SunSASL
security.provider.9=XMLDSig
security.provider.10=SunPCSC
security.provider.11=JdkLDAP
security.provider.12=JdkSASL
security.provider.13=SunPKCS11
security.provider.14=org.bouncycastle.jce.provider.BouncyCastleProvider
```

Before using it, compare the list with `$JAVA_HOME/conf/security/java.security` in your exact image: a vendor that adds or reorders providers needs the same change here. Pair it with `-Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1`. JDK 8 uses class names (`sun.security.provider.Sun`, ..., `com.sun.net.ssl.internal.ssl.Provider`) in `$JAVA_HOME/jre/lib/security/java.security`; the JDK 8 variant was not tested.

### Spring Boot

`src/main/resources/application.yml`

```yaml
server:
  port: 8443
  http2:
    enabled: true
  ssl:
    bundle: web
spring:
  ssl:
    bundle:
      jks:
        web:
          keystore:
            location: file:/etc/app/tls/server.p12
            password: ${KEYSTORE_PASSWORD}
            type: PKCS12
          options:
            enabled-protocols: [TLSv1.3, TLSv1.2]   # keep TLS 1.3 on; ML-KEM exists only in TLS 1.3
```

Spring Boot has no named-group property (checked against the 4.1.2 SSL reference). Set groups with the JVM flag in the launch environment, or with a connector customizer:

`src/main/java/com/example/PqTomcatGroups.java` (Unverified: Tomcat's `SSLHostConfig.setGroups` was tested, the Spring wiring was not)

```java
package com.example;

import org.springframework.boot.tomcat.TomcatConnectorCustomizer; // Boot 4.x; Boot 3.x: org.springframework.boot.web.embedded.tomcat
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
class PqTomcatGroups {
    @Bean
    TomcatConnectorCustomizer pqGroups() {
        return connector -> {
            for (var h : connector.findSslHostConfigs()) {
                h.setGroups("X25519MLKEM768,x25519,secp256r1,secp384r1");
            }
        };
    }
}
```

### Standalone Tomcat

`conf/server.xml` (connector excerpt; Tomcat 11.0.12+, 10.1 and 9.0 lines with the backport)

```xml
<Connector port="8443" protocol="org.apache.coyote.http11.Http11NioProtocol"
           SSLEnabled="true" maxThreads="200">
  <UpgradeProtocol className="org.apache.coyote.http2.Http2Protocol" />
  <SSLHostConfig protocols="TLSv1.3+TLSv1.2"
                 groups="X25519MLKEM768,x25519,secp256r1,secp384r1">
    <Certificate certificateKeystoreFile="conf/tls/server.p12"
                 certificateKeystorePassword="${keystore.password}"
                 certificateKeystoreType="PKCS12" />
  </SSLHostConfig>
</Connector>
```

`bin/setenv.sh` (JDK 25.0.5+: nothing needed; JDK 17/21: the agent)

```bash
#!/bin/sh
# JDK 17/21 only. Remove after moving Tomcat to JDK 25.0.5+.
CATALINA_OPTS="$CATALINA_OPTS -javaagent:/opt/pq-tls/pq-tls-agent.jar"
export CATALINA_OPTS
```

### Netty and AWS SDK code

`NettyPq.java` (client and server; groups are optional, the tested default already prefers X25519MLKEM768)

```java
import io.netty.handler.ssl.*;

final class NettyPq {
    static final String[] GROUPS = {"X25519MLKEM768", "X25519", "P-256", "P-384"};

    static SslContext client() throws Exception {
        return SslContextBuilder.forClient()
                .sslProvider(SslProvider.OPENSSL)          // netty-tcnative-boringssl-static on the class path
                .protocols("TLSv1.3", "TLSv1.2")
                .option(OpenSslContextOption.GROUPS, GROUPS) // explicit list; omit to keep the library default
                .build();
    }

    static SslContext server(javax.net.ssl.KeyManagerFactory kmf) throws Exception {
        return SslContextBuilder.forServer(kmf)
                .sslProvider(SslProvider.OPENSSL)
                .protocols("TLSv1.3", "TLSv1.2")
                .option(OpenSslContextOption.GROUPS, GROUPS)
                .build();
    }
}
```

`AwsClients.java` (AWS SDK for Java v2: CRT client; PQ by default from 2.35.11)

```java
import software.amazon.awssdk.http.crt.AwsCrtHttpClient;
import software.amazon.awssdk.http.crt.AwsCrtAsyncHttpClient;
import software.amazon.awssdk.services.kms.KmsClient;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerAsyncClient;

final class AwsClients {
    static final KmsClient KMS = KmsClient.builder()
            .httpClient(AwsCrtHttpClient.create())
            .build();
    static final SecretsManagerAsyncClient SM = SecretsManagerAsyncClient.builder()
            .httpClient(AwsCrtAsyncHttpClient.create())
            .build();
}
```

### Lambda

Zip layout (agent path, java8.al2023 / java11 / java17 / java21):

```text
function.zip
├── com/example/Handler.class
├── lib/...                      (your dependencies)
└── pq-tls/
    ├── pq-tls-agent.jar
    ├── bcprov-jdk18on-1.87.jar
    ├── bctls-jdk18on-1.87.jar
    └── bcutil-jdk18on-1.87.jar
```

`template.yaml` (SAM)

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Parameters:
  Java8:
    Type: String
    AllowedValues: ['true', 'false']
    Default: 'false'
Conditions:
  IsJava8: !Equals [!Ref Java8, 'true']
Resources:
  Fn:
    Type: AWS::Serverless::Function
    Properties:
      Runtime: java21              # java25: delete the Environment block, nothing else needed
      Handler: com.example.Handler::handleRequest
      CodeUri: build/function.zip
      MemorySize: 1024
      Timeout: 30
      Architectures: [arm64]
      Environment:
        Variables:
          JAVA_TOOL_OPTIONS: !If
            - IsJava8
            - -javaagent:/var/task/pq-tls/pq-tls-agent.jar -Djdk.tls.client.protocols=TLSv1.3,TLSv1.2
            - -javaagent:/var/task/pq-tls/pq-tls-agent.jar
```

`lambda.yaml` (plain CloudFormation)

```yaml
AWSTemplateFormatVersion: '2010-09-09'
Parameters:
  CodeBucket: {Type: String}
  CodeKey: {Type: String}
  RoleArn: {Type: String}
Resources:
  Fn:
    Type: AWS::Lambda::Function
    Properties:
      Runtime: java21
      Handler: com.example.Handler::handleRequest
      Role: !Ref RoleArn
      Code: {S3Bucket: !Ref CodeBucket, S3Key: !Ref CodeKey}
      MemorySize: 1024
      Timeout: 30
      Architectures: [arm64]
      Environment:
        Variables:
          JAVA_TOOL_OPTIONS: -javaagent:/var/task/pq-tls/pq-tls-agent.jar
```

`lambda.tf` (Terraform)

```hcl
resource "aws_lambda_function" "fn" {
  function_name = "orders-java"
  runtime       = "java21" # java25: remove the environment block
  handler       = "com.example.Handler::handleRequest"
  role          = var.role_arn
  filename      = "build/function.zip"
  source_code_hash = filebase64sha256("build/function.zip")
  memory_size   = 1024
  timeout       = 30
  architectures = ["arm64"]
  environment {
    variables = {
      JAVA_TOOL_OPTIONS = "-javaagent:/var/task/pq-tls/pq-tls-agent.jar"
    }
  }
}
```

`Dockerfile.lambda` (Lambda container image, java21 base; for java25 drop the COPY and ENV lines)

```dockerfile
FROM public.ecr.aws/lambda/java:21
COPY build/classes/ ${LAMBDA_TASK_ROOT}/
COPY build/dependency/ ${LAMBDA_TASK_ROOT}/lib/
COPY pq-tls/ ${LAMBDA_TASK_ROOT}/pq-tls/
ENV JAVA_TOOL_OPTIONS="-javaagent:/var/task/pq-tls/pq-tls-agent.jar"
CMD ["com.example.Handler::handleRequest"]
```

### Containers (Fargate, ECS, EKS)

`Dockerfile` (preferred: JDK 25.0.5+, no PQ-specific lines)

```dockerfile
FROM amazoncorretto:25-al2023-headless
# or: FROM eclipse-temurin:25-jre  /  gcr.io/distroless/java25-debian13 (check the tag exists for your registry mirror)
COPY build/libs/app.jar /app/app.jar
USER 1000
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

`Dockerfile.jdk21-agent` (JDK 17/21 until the upgrade)

```dockerfile
FROM amazoncorretto:21-al2023-headless
COPY pq-tls/ /opt/pq-tls/
COPY build/libs/app.jar /app/app.jar
ENV JAVA_TOOL_OPTIONS="-javaagent:/opt/pq-tls/pq-tls-agent.jar"
USER 1000
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

`Dockerfile.distroless-agent` (distroless has no shell; ENV still works because the JVM reads JAVA_TOOL_OPTIONS itself)

```dockerfile
FROM gcr.io/distroless/java21-debian12:nonroot
COPY pq-tls/ /opt/pq-tls/
COPY build/libs/app.jar /app/app.jar
ENV JAVA_TOOL_OPTIONS="-javaagent:/opt/pq-tls/pq-tls-agent.jar"
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
```

`Dockerfile.static` (static provider registration instead of the agent)

```dockerfile
FROM eclipse-temurin:21-jre
COPY pq-tls/bcprov-jdk18on-1.87.jar pq-tls/bctls-jdk18on-1.87.jar pq-tls/bcutil-jdk18on-1.87.jar /opt/pq-tls/
COPY pq-tls/bc-static.security /opt/pq-tls/bc-static.security
COPY build/libs/app.jar /app/app.jar
ENV JAVA_TOOL_OPTIONS="-Djava.security.properties=/opt/pq-tls/bc-static.security -Djdk.tls.namedGroups=X25519MLKEM768,x25519,secp256r1,secp384r1"
# -jar ignores -cp, so put the BC jars in the jar manifest Class-Path, or run with -cp and the main class:
ENTRYPOINT ["java", "-cp", "/app/app.jar:/opt/pq-tls/*", "com.example.Main"]
```

`taskdef.json` (ECS / Fargate; only needed on JDK 17/21 if the image does not already set it)

```json
{
  "family": "orders-java",
  "requiresCompatibilities": ["FARGATE"],
  "networkMode": "awsvpc",
  "cpu": "1024",
  "memory": "2048",
  "runtimePlatform": {"cpuArchitecture": "ARM64", "operatingSystemFamily": "LINUX"},
  "executionRoleArn": "arn:aws:iam::111122223333:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "app",
      "image": "111122223333.dkr.ecr.eu-west-1.amazonaws.com/orders-java@sha256:<digest>",
      "essential": true,
      "portMappings": [{"containerPort": 8443, "protocol": "tcp"}],
      "environment": [
        {"name": "JAVA_TOOL_OPTIONS", "value": "-javaagent:/opt/pq-tls/pq-tls-agent.jar"}
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {"awslogs-group": "/ecs/orders-java", "awslogs-region": "eu-west-1", "awslogs-stream-prefix": "app"}
      }
    }
  ]
}
```

`ecs.tf` (Terraform)

```hcl
resource "aws_ecs_task_definition" "app" {
  family                   = "orders-java"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = var.execution_role_arn
  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }
  container_definitions = jsonencode([{
    name         = "app"
    image        = var.image # pin by digest
    essential    = true
    portMappings = [{ containerPort = 8443, protocol = "tcp" }]
    environment  = [{ name = "JAVA_TOOL_OPTIONS", value = "-javaagent:/opt/pq-tls/pq-tls-agent.jar" }]
  }])
}
```

`ecs.yaml` (CloudFormation)

```yaml
Resources:
  TaskDef:
    Type: AWS::ECS::TaskDefinition
    Properties:
      Family: orders-java
      RequiresCompatibilities: [FARGATE]
      NetworkMode: awsvpc
      Cpu: '1024'
      Memory: '2048'
      ExecutionRoleArn: !Ref ExecutionRoleArn
      RuntimePlatform: {CpuArchitecture: ARM64, OperatingSystemFamily: LINUX}
      ContainerDefinitions:
        - Name: app
          Image: !Ref Image
          Essential: true
          PortMappings: [{ContainerPort: 8443, Protocol: tcp}]
          Environment:
            - {Name: JAVA_TOOL_OPTIONS, Value: -javaagent:/opt/pq-tls/pq-tls-agent.jar}
Parameters:
  ExecutionRoleArn: {Type: String}
  Image: {Type: String}
```

`deployment.yaml` (EKS)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders-java
spec:
  replicas: 2
  selector:
    matchLabels: {app: orders-java}
  template:
    metadata:
      labels: {app: orders-java}
    spec:
      containers:
        - name: app
          image: 111122223333.dkr.ecr.eu-west-1.amazonaws.com/orders-java@sha256:<digest>
          ports: [{containerPort: 8443}]
          env:
            - name: JAVA_TOOL_OPTIONS
              value: "-javaagent:/opt/pq-tls/pq-tls-agent.jar"
          readinessProbe:
            tcpSocket: {port: 8443}
```

### EC2

`/etc/systemd/system/orders-java.service`

```ini
[Unit]
Description=orders-java
After=network-online.target
Wants=network-online.target

[Service]
User=orders
# JDK 25.0.5+: delete the Environment line.
Environment="JAVA_TOOL_OPTIONS=-javaagent:/opt/pq-tls/pq-tls-agent.jar"
ExecStart=/usr/lib/jvm/java-21-amazon-corretto/bin/java -jar /opt/orders/app.jar
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

`/etc/systemd/system/orders-java.service.d/pq-tls.conf` (drop-in, when you cannot edit the unit)

```ini
[Service]
Environment="JAVA_TOOL_OPTIONS=-javaagent:/opt/pq-tls/pq-tls-agent.jar"
```

`pq-tls-ssm.yaml` (SSM Command document: install the kit from S3 and add the drop-in)

```yaml
schemaVersion: '2.2'
description: Install the pq-tls Java agent and enable it for one systemd service.
parameters:
  Service: {type: String}
  KitS3Uri: {type: String, description: 's3://bucket/pq-tls-1.87.tgz'}
mainSteps:
  - action: aws:runShellScript
    name: install
    inputs:
      runCommand:
        - set -euo pipefail
        - mkdir -p /opt/pq-tls
        - aws s3 cp '{{ KitS3Uri }}' /tmp/pq-tls.tgz
        - tar -xzf /tmp/pq-tls.tgz -C /opt/pq-tls
        - mkdir -p '/etc/systemd/system/{{ Service }}.service.d'
        - printf '[Service]\nEnvironment="JAVA_TOOL_OPTIONS=-javaagent:/opt/pq-tls/pq-tls-agent.jar"\n' > '/etc/systemd/system/{{ Service }}.service.d/pq-tls.conf'
        - systemctl daemon-reload
        - systemctl restart '{{ Service }}'
        - journalctl -u '{{ Service }}' -n 50 --no-pager | grep -m1 'pq-tls agent'
```
