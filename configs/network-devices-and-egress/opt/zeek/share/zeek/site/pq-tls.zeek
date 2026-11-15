##! pq-tls.zeek - flag TLS sessions whose negotiated key exchange is not hybrid post-quantum.
##! Needs Zeek 7.1+ (SSL::ec_curves knows 0x11EC = X25519MLKEM768).
@load base/protocols/ssl
@load base/frameworks/notice

module PQTLS;

export {
    redef enum Notice::Type += { PQTLS::Classical_Key_Exchange };

    ## Groups counted as post-quantum (hybrid ML-KEM).
    const pq_groups: set[string] = {
        "X25519MLKEM768", "SecP256r1MLKEM768", "SecP384r1MLKEM1024",
    } &redef;

    ## Add a boolean column "pq" to ssl.log.
    redef record SSL::Info += {
        pq: bool &log &optional;
    };
}

event ssl_established(c: connection) &priority=3
    {
    if ( ! c?$ssl ) return;
    local grp = c$ssl?$curve ? c$ssl$curve : "none";
    c$ssl$pq = grp in pq_groups;
    if ( ! c$ssl$pq )
        NOTICE([$note=PQTLS::Classical_Key_Exchange,
                $msg=fmt("non-PQ TLS key exchange: group=%s version=%s sni=%s", grp,
                         c$ssl?$version ? c$ssl$version : "?",
                         c$ssl?$server_name ? c$ssl$server_name : "-"),
                $conn=c,
                $identifier=cat(c$id$resp_h, c$id$resp_p, grp),
                $suppress_for=1hr]);
    }
