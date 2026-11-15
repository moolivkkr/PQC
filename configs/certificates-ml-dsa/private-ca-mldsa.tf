# private-ca-mldsa.tf - ML-DSA-65 root CA in AWS Private CA, self-signed and activated, plus a KMS ML-DSA key
resource "aws_acmpca_certificate_authority" "mldsa_root" {
  type = "ROOT"

  certificate_authority_configuration {
    key_algorithm     = "ML_DSA_65"
    signing_algorithm = "ML_DSA_65"
    subject {
      common_name  = "Example ML-DSA Root"
      organization = "Example"
    }
  }

  permanent_deletion_time_in_days = 7
}

resource "aws_acmpca_certificate" "mldsa_root" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.mldsa_root.arn
  certificate_signing_request = aws_acmpca_certificate_authority.mldsa_root.certificate_signing_request
  signing_algorithm           = "ML_DSA_65"
  template_arn                = "arn:aws:acm-pca:::template/RootCACertificate/V1"

  validity {
    type  = "YEARS"
    value = 10
  }
}

resource "aws_acmpca_certificate_authority_certificate" "mldsa_root" {
  certificate_authority_arn = aws_acmpca_certificate_authority.mldsa_root.arn
  certificate               = aws_acmpca_certificate.mldsa_root.certificate
  certificate_chain         = aws_acmpca_certificate.mldsa_root.certificate_chain
}

# End-entity certificate from a CSR made with: openssl genpkey -algorithm ML-DSA-44
resource "aws_acmpca_certificate" "svc" {
  certificate_authority_arn   = aws_acmpca_certificate_authority.mldsa_root.arn
  certificate_signing_request = file("${path.module}/leaf.csr")
  signing_algorithm           = "ML_DSA_65"
  template_arn                = "arn:aws:acm-pca:::template/EndEntityCertificate/V1"

  validity {
    type  = "DAYS"
    value = 90
  }

  depends_on = [aws_acmpca_certificate_authority_certificate.mldsa_root]
}

resource "aws_kms_key" "mldsa_signing" {
  description              = "ML-DSA-65 signing key"
  customer_master_key_spec = "ML_DSA_65"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = 7
}
