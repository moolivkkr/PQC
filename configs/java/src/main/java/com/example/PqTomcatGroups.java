package com.example;

import org.springframework.boot.tomcat.TomcatConnectorCustomizer; // Boot 3.x: org.springframework.boot.web.embedded.tomcat.TomcatConnectorCustomizer
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
