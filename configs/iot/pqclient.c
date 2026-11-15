/* pqclient.c - wolfSSL TLS 1.3 client offering X25519MLKEM768 (hybrid) first.
 * Run: ./pqclient HOST PORT CAFILE [classic] */
#include <wolfssl/options.h>
#include <wolfssl/ssl.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <netdb.h>
#include <sys/socket.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 4) { fprintf(stderr, "usage: %s host port ca [classic]\n", argv[0]); return 2; }
    int classic = argc > 4 && strcmp(argv[4], "classic") == 0;
    struct addrinfo hints = {0}, *ai; hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(argv[1], argv[2], &hints, &ai) != 0) return 2;
    int fd = socket(ai->ai_family, SOCK_STREAM, 0);
    if (connect(fd, ai->ai_addr, ai->ai_addrlen) != 0) { perror("connect"); return 2; }

    wolfSSL_Init();
    WOLFSSL_CTX *ctx = wolfSSL_CTX_new(wolfTLSv1_3_client_method());
    wolfSSL_CTX_load_verify_locations(ctx, argv[3], NULL);
    /* Supported groups, in preference order. */
    int pq[] = { WOLFSSL_X25519MLKEM768, WOLFSSL_ECC_X25519, WOLFSSL_ECC_SECP256R1 };
    int cl[] = { WOLFSSL_ECC_X25519, WOLFSSL_ECC_SECP256R1 };
    if (wolfSSL_CTX_set_groups(ctx, classic ? cl : pq, classic ? 2 : 3) != WOLFSSL_SUCCESS)
        fprintf(stderr, "set_groups failed\n");
    WOLFSSL *ssl = wolfSSL_new(ctx);
    /* Key share sent in the first ClientHello (avoids a HelloRetryRequest round trip). */
    wolfSSL_UseKeyShare(ssl, classic ? WOLFSSL_ECC_X25519 : WOLFSSL_X25519MLKEM768);
    wolfSSL_UseSNI(ssl, WOLFSSL_SNI_HOST_NAME, argv[1], strlen(argv[1]));
    wolfSSL_set_fd(ssl, fd);
    if (wolfSSL_connect(ssl) != WOLFSSL_SUCCESS) {
        char e[80]; printf("HANDSHAKE_FAIL %s\n", wolfSSL_ERR_error_string(wolfSSL_get_error(ssl, 0), e));
        return 1;
    }
    printf("HANDSHAKE_OK version=%s group=%s\n", wolfSSL_get_version(ssl), wolfSSL_get_curve_name(ssl));
    wolfSSL_shutdown(ssl); wolfSSL_free(ssl); wolfSSL_CTX_free(ctx); close(fd);
    return 0;
}
