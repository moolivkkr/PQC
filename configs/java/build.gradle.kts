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
