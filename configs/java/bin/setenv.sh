#!/bin/sh
# JDK 17/21 only. Remove after moving Tomcat to JDK 25.0.5+.
CATALINA_OPTS="$CATALINA_OPTS -Djava.security.properties=/opt/pq-tls/pq-tls.security -javaagent:/opt/pq-tls/pq-tls-agent.jar"
export CATALINA_OPTS
