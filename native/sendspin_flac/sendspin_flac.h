#ifndef SENDSPIN_FLAC_H
#define SENDSPIN_FLAC_H

#include <stdint.h>
#include <stddef.h>

#ifdef _WIN32
#define SENDSPIN_FLAC_EXPORT __declspec(dllexport)
#else
#define SENDSPIN_FLAC_EXPORT __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef struct SendspinFlacDecoder SendspinFlacDecoder;

/// Create a new FLAC decoder.
SENDSPIN_FLAC_EXPORT SendspinFlacDecoder* sendspin_flac_new(void);

/// Decode a buffer of FLAC-encoded data into interleaved PCM samples.
///
/// @param decoder      The decoder instance
/// @param input        Pointer to FLAC-encoded bytes
/// @param input_len    Number of input bytes
/// @param output       Pre-allocated buffer for interleaved int32 PCM output
/// @param output_capacity  Maximum number of int32 samples output can hold
/// @return Number of int32 samples written to output, or -1 on error
SENDSPIN_FLAC_EXPORT int sendspin_flac_decode(
    SendspinFlacDecoder* decoder,
    const uint8_t* input,
    size_t input_len,
    int32_t* output,
    size_t output_capacity);

/// Reset the decoder state (e.g., on stream/clear).
SENDSPIN_FLAC_EXPORT void sendspin_flac_reset(SendspinFlacDecoder* decoder);

/// Free the decoder and all associated resources.
SENDSPIN_FLAC_EXPORT void sendspin_flac_free(SendspinFlacDecoder* decoder);

#ifdef __cplusplus
}
#endif

#endif // SENDSPIN_FLAC_H
