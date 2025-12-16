#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <openssl/evp.h>
#include <openssl/rand.h>
#include <openssl/err.h>

#define AES_KEY_SIZE 32
#define AES_IV_SIZE 12
#define AES_TAG_SIZE 16
#define BUFFER_SIZE 4096

typedef struct {
    unsigned char key[AES_KEY_SIZE];
    unsigned char iv[AES_IV_SIZE];
    unsigned char tag[AES_TAG_SIZE];
} aes_gcm_context_t;

static void handle_openssl_error(const char *msg) {
    fprintf(stderr, "OpenSSL Error in %s: ", msg);
    ERR_print_errors_fp(stderr);
}

int generate_random_key(unsigned char *key, size_t key_len) {
    if (RAND_bytes(key, key_len) != 1) {
        handle_openssl_error("generate_random_key");
        return -1;
    }
    return 0;
}

int encrypt_file_data(const unsigned char *plaintext, size_t plaintext_len,
                     const unsigned char *key, const unsigned char *iv,
                     unsigned char *ciphertext, unsigned char *tag) {
    EVP_CIPHER_CTX *ctx = NULL;
    int len, ciphertext_len;
    int ret = -1;

    if (!plaintext || !key || !iv || !ciphertext || !tag) {
        fprintf(stderr, "Invalid parameters to encrypt_file_data\n");
        return -1;
    }

    ctx = EVP_CIPHER_CTX_new();
    if (!ctx) {
        handle_openssl_error("EVP_CIPHER_CTX_new");
        return -1;
    }

    if (EVP_EncryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) != 1) {
        handle_openssl_error("EVP_EncryptInit_ex");
        goto cleanup;
    }

    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, AES_IV_SIZE, NULL) != 1) {
        handle_openssl_error("EVP_CTRL_GCM_SET_IVLEN");
        goto cleanup;
    }

    if (EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv) != 1) {
        handle_openssl_error("EVP_EncryptInit_ex key/iv");
        goto cleanup;
    }

    if (EVP_EncryptUpdate(ctx, ciphertext, &len, plaintext, plaintext_len) != 1) {
        handle_openssl_error("EVP_EncryptUpdate");
        goto cleanup;
    }
    ciphertext_len = len;

    if (EVP_EncryptFinal_ex(ctx, ciphertext + len, &len) != 1) {
        handle_openssl_error("EVP_EncryptFinal_ex");
        goto cleanup;
    }
    ciphertext_len += len;

    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, AES_TAG_SIZE, tag) != 1) {
        handle_openssl_error("EVP_CTRL_GCM_GET_TAG");
        goto cleanup;
    }

    ret = ciphertext_len;

cleanup:
    if (ctx) EVP_CIPHER_CTX_free(ctx);
    return ret;
}

int decrypt_file_data(const unsigned char *ciphertext, size_t ciphertext_len,
                     const unsigned char *key, const unsigned char *iv,
                     const unsigned char *tag, unsigned char *plaintext) {
    EVP_CIPHER_CTX *ctx = NULL;
    int len, plaintext_len;
    int ret = -1;

    if (!ciphertext || !key || !iv || !tag || !plaintext) {
        fprintf(stderr, "Invalid parameters to decrypt_file_data\n");
        return -1;
    }

    ctx = EVP_CIPHER_CTX_new();
    if (!ctx) {
        handle_openssl_error("EVP_CIPHER_CTX_new");
        return -1;
    }

    if (EVP_DecryptInit_ex(ctx, EVP_aes_256_gcm(), NULL, NULL, NULL) != 1) {
        handle_openssl_error("EVP_DecryptInit_ex");
        goto cleanup;
    }

    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, AES_IV_SIZE, NULL) != 1) {
        handle_openssl_error("EVP_CTRL_GCM_SET_IVLEN");
        goto cleanup;
    }

    if (EVP_DecryptInit_ex(ctx, NULL, NULL, key, iv) != 1) {
        handle_openssl_error("EVP_DecryptInit_ex key/iv");
        goto cleanup;
    }

    if (EVP_DecryptUpdate(ctx, plaintext, &len, ciphertext, ciphertext_len) != 1) {
        handle_openssl_error("EVP_DecryptUpdate");
        goto cleanup;
    }
    plaintext_len = len;

    if (EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, AES_TAG_SIZE, (void*)tag) != 1) {
        handle_openssl_error("EVP_CTRL_GCM_SET_TAG");
        goto cleanup;
    }

    if (EVP_DecryptFinal_ex(ctx, plaintext + len, &len) != 1) {
        handle_openssl_error("EVP_DecryptFinal_ex - Authentication failed");
        goto cleanup;
    }
    plaintext_len += len;

    ret = plaintext_len;

cleanup:
    if (ctx) EVP_CIPHER_CTX_free(ctx);
    return ret;
}

int encrypt_file(const char *input_file, const char *output_file, const unsigned char *key) {
    FILE *in_fp = NULL, *out_fp = NULL;
    unsigned char iv[AES_IV_SIZE];
    unsigned char tag[AES_TAG_SIZE];
    unsigned char buffer[BUFFER_SIZE];
    unsigned char encrypted[BUFFER_SIZE + 16];
    size_t bytes_read;
    int encrypted_len;
    int ret = -1;

    if (generate_random_key(iv, AES_IV_SIZE) != 0) {
        fprintf(stderr, "Failed to generate IV\n");
        return -1;
    }

    in_fp = fopen(input_file, "rb");
    if (!in_fp) {
        perror("fopen input file");
        return -1;
    }

    out_fp = fopen(output_file, "wb");
    if (!out_fp) {
        perror("fopen output file");
        goto cleanup;
    }

    // Write IV to beginning of file
    if (fwrite(iv, 1, AES_IV_SIZE, out_fp) != AES_IV_SIZE) {
        perror("fwrite IV");
        goto cleanup;
    }

    // Encrypt file in chunks
    while ((bytes_read = fread(buffer, 1, BUFFER_SIZE, in_fp)) > 0) {
        encrypted_len = encrypt_file_data(buffer, bytes_read, key, iv, encrypted, tag);
        if (encrypted_len < 0) {
            fprintf(stderr, "Encryption failed\n");
            goto cleanup;
        }

        if (fwrite(encrypted, 1, encrypted_len, out_fp) != (size_t)encrypted_len) {
            perror("fwrite encrypted data");
            goto cleanup;
        }
    }

    // Write authentication tag
    if (fwrite(tag, 1, AES_TAG_SIZE, out_fp) != AES_TAG_SIZE) {
        perror("fwrite tag");
        goto cleanup;
    }

    ret = 0;

cleanup:
    if (in_fp) fclose(in_fp);
    if (out_fp) fclose(out_fp);
    return ret;
}

// Test function
int main(int argc, char *argv[]) {
    if (argc != 4) {
        fprintf(stderr, "Usage: %s <input_file> <output_file> <key_hex>\n", argv[0]);
        return 1;
    }

    unsigned char key[AES_KEY_SIZE];
    
    // Generate random key for demo
    if (generate_random_key(key, AES_KEY_SIZE) != 0) {
        fprintf(stderr, "Failed to generate key\n");
        return 1;
    }

    printf("Encrypting file with AES-256-GCM...\n");
    if (encrypt_file(argv[1], argv[2], key) == 0) {
        printf("File encrypted successfully\n");
        return 0;
    } else {
        printf("Encryption failed\n");
        return 1;
    }
}
