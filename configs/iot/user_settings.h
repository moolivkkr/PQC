/* user_settings.h - wolfSSL for an MCU TLS 1.3 client with hybrid ML-KEM (X25519MLKEM768).
 * Compile with -DWOLFSSL_USER_SETTINGS. */
#ifndef WOLFSSL_USER_SETTINGS_H
#define WOLFSSL_USER_SETTINGS_H

/* Platform (adjust to your port) */
#define FREERTOS
#define WOLFSSL_LWIP
#define NO_FILESYSTEM
#define NO_WRITEV
#define SINGLE_THREADED            /* remove if several tasks use TLS */
#define WOLFSSL_SMALL_STACK        /* move big buffers to heap; ML-KEM needs it on MCUs */

/* TLS 1.3 client */
#define WOLFSSL_TLS13
#define NO_OLD_TLS
#define HAVE_TLS_EXTENSIONS
#define HAVE_SUPPORTED_CURVES
#define HAVE_SNI
#define HAVE_HKDF
#define HAVE_AESGCM
#define WOLFSSL_SHA384
#define WC_RSA_PSS
#define NO_WOLFSSL_SERVER          /* device is a client only */

/* Classical key exchange kept for fallback (IoT Core is classical) */
#define HAVE_ECC
#define ECC_TIMING_RESISTANT
#define HAVE_CURVE25519
#define TFM_TIMING_RESISTANT
#define WC_RSA_BLINDING

/* Post-quantum: ML-KEM (FIPS 203) and the hybrid groups */
#define WOLFSSL_HAVE_MLKEM
#define WOLFSSL_WC_MLKEM           /* native implementation */
#define WOLFSSL_SHA3
#define WOLFSSL_SHAKE128
#define WOLFSSL_SHAKE256
#define WOLFSSL_NO_ML_KEM_512      /* keep only ML-KEM-768 (X25519MLKEM768) */
#define WOLFSSL_NO_ML_KEM_1024
/* Lower RAM at some speed cost (wolfSSL memory blog): */
#define WOLFSSL_MLKEM_ENCAPSULATE_SMALL_MEM
#define WOLFSSL_MLKEM_MAKEKEY_SMALL_MEM

/* RNG: replace with your hardware TRNG hook */
/* #define CUSTOM_RAND_GENERATE_BLOCK my_trng_block */

#endif /* WOLFSSL_USER_SETTINGS_H */
