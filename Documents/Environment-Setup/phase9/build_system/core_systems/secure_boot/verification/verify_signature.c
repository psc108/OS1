#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/rsa.h>
#include <openssl/sha.h>

int verify_boot_signature(const char *image_path, const char *sig_path, const char *cert_path) {
    FILE *image_file, *sig_file, *cert_file;
    EVP_PKEY *pkey = NULL;
    X509 *cert = NULL;
    EVP_MD_CTX *mdctx = NULL;
    unsigned char *image_data = NULL, *signature = NULL;
    size_t image_size, sig_size;
    int ret = -1;

    // Load certificate
    cert_file = fopen(cert_path, "r");
    if (!cert_file) {
        fprintf(stderr, "Failed to open certificate file\n");
        goto cleanup;
    }
    
    cert = PEM_read_X509(cert_file, NULL, NULL, NULL);
    fclose(cert_file);
    if (!cert) {
        fprintf(stderr, "Failed to parse certificate\n");
        goto cleanup;
    }
    
    pkey = X509_get_pubkey(cert);
    if (!pkey) {
        fprintf(stderr, "Failed to extract public key\n");
        goto cleanup;
    }

    // Load image
    image_file = fopen(image_path, "rb");
    if (!image_file) {
        fprintf(stderr, "Failed to open image file\n");
        goto cleanup;
    }
    
    fseek(image_file, 0, SEEK_END);
    image_size = ftell(image_file);
    fseek(image_file, 0, SEEK_SET);
    
    image_data = malloc(image_size);
    if (!image_data || fread(image_data, 1, image_size, image_file) != image_size) {
        fprintf(stderr, "Failed to read image data\n");
        fclose(image_file);
        goto cleanup;
    }
    fclose(image_file);

    // Load signature
    sig_file = fopen(sig_path, "rb");
    if (!sig_file) {
        fprintf(stderr, "Failed to open signature file\n");
        goto cleanup;
    }
    
    fseek(sig_file, 0, SEEK_END);
    sig_size = ftell(sig_file);
    fseek(sig_file, 0, SEEK_SET);
    
    signature = malloc(sig_size);
    if (!signature || fread(signature, 1, sig_size, sig_file) != sig_size) {
        fprintf(stderr, "Failed to read signature\n");
        fclose(sig_file);
        goto cleanup;
    }
    fclose(sig_file);

    // Verify signature
    mdctx = EVP_MD_CTX_new();
    if (!mdctx) {
        fprintf(stderr, "Failed to create digest context\n");
        goto cleanup;
    }
    
    if (EVP_DigestVerifyInit(mdctx, NULL, EVP_sha256(), NULL, pkey) <= 0) {
        fprintf(stderr, "Failed to initialize verification\n");
        goto cleanup;
    }
    
    if (EVP_DigestVerifyUpdate(mdctx, image_data, image_size) <= 0) {
        fprintf(stderr, "Failed to update digest\n");
        goto cleanup;
    }
    
    ret = EVP_DigestVerifyFinal(mdctx, signature, sig_size);
    if (ret == 1) {
        printf("Signature verification: SUCCESS\n");
        ret = 0;
    } else {
        printf("Signature verification: FAILED\n");
        ret = -1;
    }

cleanup:
    if (mdctx) EVP_MD_CTX_free(mdctx);
    if (pkey) EVP_PKEY_free(pkey);
    if (cert) X509_free(cert);
    free(image_data);
    free(signature);
    
    return ret;
}

int main(int argc, char *argv[]) {
    if (argc != 4) {
        fprintf(stderr, "Usage: %s <image> <signature> <certificate>\n", argv[0]);
        return 1;
    }
    
    return verify_boot_signature(argv[1], argv[2], argv[3]);
}
