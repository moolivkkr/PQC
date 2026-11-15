import software.amazon.awssdk.http.crt.AwsCrtAsyncHttpClient;
import software.amazon.awssdk.http.crt.AwsCrtHttpClient;
import software.amazon.awssdk.services.kms.KmsClient;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerAsyncClient;

final class AwsClients {
    static final KmsClient KMS = KmsClient.builder()
            .httpClient(AwsCrtHttpClient.create())
            .build();
    static final SecretsManagerAsyncClient SM = SecretsManagerAsyncClient.builder()
            .httpClient(AwsCrtAsyncHttpClient.create())
            .build();
}
