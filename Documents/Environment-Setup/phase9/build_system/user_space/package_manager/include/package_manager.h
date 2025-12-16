#ifndef PACKAGE_MANAGER_H
#define PACKAGE_MANAGER_H

#include <sys/types.h>
#include <openssl/evp.h>
#include <openssl/rsa.h>

#define PACKAGE_MAGIC "SECPKG01"
#define MAX_PACKAGE_NAME 128
#define MAX_SIGNATURE_SIZE 512
#define MAX_HASH_SIZE 64

struct package_header {
    char magic[8];
    uint32_t version;
    uint32_t header_size;
    uint64_t content_size;
    uint64_t content_offset;
    uint32_t signature_size;
    uint64_t signature_offset;
    char package_name[MAX_PACKAGE_NAME];
    char hash_algorithm[32];
    uint8_t content_hash[MAX_HASH_SIZE];
};

struct package_signature {
    char algorithm[32];
    uint32_t key_id;
    uint32_t signature_size;
    uint8_t signature_data[MAX_SIGNATURE_SIZE];
};

struct package_verification_context {
    EVP_PKEY *public_key;
    const char *trusted_key_path;
    int verification_level;
};

int verify_package_integrity(const char *package_path, struct package_verification_context *ctx);
int verify_package_signature(const char *package_path, struct package_verification_context *ctx);
int calculate_package_hash(const char *package_path, uint8_t *hash, size_t hash_size);
int load_trusted_keys(const char *key_directory, struct package_verification_context *ctx);
int validate_package_chain(const char *package_path, struct package_verification_context *ctx);

#endif /* PACKAGE_MANAGER_H */
