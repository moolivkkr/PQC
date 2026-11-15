#!/bin/sh
# check-jdk-pq.sh <image>  - read the JDK `release` file from a container image without running it.
# PASS: JAVA_VERSION >= 25. WARN: 8-21 (needs the Bouncy Castle JSSE agent; check JAVA_TOOL_OPTIONS).
# Needs: docker (or podman with the same CLI).
img="$1"
cid=$(docker create ${DOCKER_CREATE_ARGS:-} "$img" /bin/true) || exit 2
trap 'docker rm -f "$cid" >/dev/null 2>&1' EXIT
jhome=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$img" | sed -n 's/^JAVA_HOME=//p' | head -1)
for p in "${jhome:-/nonexistent}/release" /opt/java/openjdk/release /usr/lib/jvm/default-jvm/release /usr/lib/jvm/java/release; do
  if docker cp "$cid:$p" - 2>/dev/null | tar -xO 2>/dev/null > /tmp/jdk-release.$$; then
    [ -s /tmp/jdk-release.$$ ] && break
  fi
done
ver=$(sed -n 's/^JAVA_VERSION="\{0,1\}\([^"]*\)"\{0,1\}/\1/p' /tmp/jdk-release.$$ 2>/dev/null); rm -f /tmp/jdk-release.$$
[ -z "$ver" ] && { echo "SKIP $img: no JDK release file found"; exit 0; }
major=$(echo "$ver" | sed -E 's/^1\.([0-9]+).*/\1/; s/^([0-9]+).*/\1/')
jto=$(docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$img" | sed -n 's/^JAVA_TOOL_OPTIONS=//p')
if [ "$major" -ge 25 ]; then
  echo "PASS $img: JDK $ver (ML-KEM hybrid groups on by default)"
elif echo "$jto" | grep -q 'pq-tls-agent.jar\|bctls'; then
  echo "PASS $img: JDK $ver with Bouncy Castle JSSE agent ($jto)"
else
  echo "WARN $img: JDK $ver has no ML-KEM TLS group. Add -javaagent:/opt/pq-tls/pq-tls-agent.jar or move to JDK 25"; exit 1
fi
