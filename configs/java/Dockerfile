FROM amazoncorretto:25-al2023-headless
# or: FROM eclipse-temurin:25-jre
COPY build/libs/app.jar /app/app.jar
USER 1000
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
