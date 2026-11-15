/* FreeRTOS-Plus/Source/Application-Protocols/network_transport/transport_wolfSSL.c
 * In TLS_FreeRTOS_Connect(), after:  pxNetworkContext->ssl = wolfSSL_new( pxNetworkContext->sslCtx );
 * add the group order and the first key share. Keeps X25519/P-256 for AWS IoT Core (classical).
 */
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
