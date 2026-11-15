static int pqGroups[] = { WOLFSSL_X25519MLKEM768, WOLFSSL_ECC_X25519, WOLFSSL_ECC_SECP256R1 };

if( wolfSSL_set_groups( pxNetworkContext->ssl, pqGroups,
                        ( int ) ( sizeof( pqGroups ) / sizeof( pqGroups[ 0 ] ) ) ) != WOLFSSL_SUCCESS )
{
    LogWarn( ( "wolfSSL_set_groups failed; using library defaults." ) );
}
/* Send the hybrid share in ClientHello 1 (avoids a HelloRetryRequest with PQ-only brokers). */
if( wolfSSL_UseKeyShare( pxNetworkContext->ssl, WOLFSSL_X25519MLKEM768 ) != WOLFSSL_SUCCESS )
{
    LogWarn( ( "ML-KEM key share unavailable; is WOLFSSL_HAVE_MLKEM defined?" ) );
}
/* After wolfSSL_connect() succeeds, log what was negotiated: */
/* LogInfo( ( "TLS group: %s", wolfSSL_get_curve_name( pxNetworkContext->ssl ) ) ); */
