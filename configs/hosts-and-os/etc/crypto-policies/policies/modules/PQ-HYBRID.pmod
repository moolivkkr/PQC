# Custom subpolicy: add the X25519+ML-KEM-768 hybrid group first for TLS and SSH,
# leave every other algorithm as the base policy has it.
# Apply: update-crypto-policies --set DEFAULT:PQ-HYBRID
group = +X25519-MLKEM768
