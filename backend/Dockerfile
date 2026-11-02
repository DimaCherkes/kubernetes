# ==========================================
# Stage 1: Build stage with Maven & Java 21
# ==========================================
FROM maven:3.9.9-eclipse-temurin-21-alpine AS builder

WORKDIR /build

# Pre-cache Maven dependencies
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy application source code
COPY src ./src

# Package executable fat jar (skipping unit tests per prototype spec)
RUN mvn clean package -DskipTests

# ==========================================
# Stage 2: Runtime stage with minimal JRE 21
# ==========================================
FROM eclipse-temurin:21-jre-alpine AS runner

WORKDIR /app

# Create a non-root system group and user (UID/GID 1001)
RUN addgroup -g 1001 -S spring && adduser -u 1001 -S spring -G spring

# Copy packaged jar from builder stage and assign ownership
COPY --from=builder --chown=spring:spring /build/target/*.jar /app/app.jar

# JVM container support & flags
ENV JAVA_TOOL_OPTIONS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -Djava.security.egd=file:/dev/./urandom"

# Switch to non-root user
USER spring:spring

EXPOSE 8080

ENTRYPOINT ["java", "-jar", "/app/app.jar"]
