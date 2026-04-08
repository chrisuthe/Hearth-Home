#include "sendspin_flac.h"
#include <FLAC/stream_decoder.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

struct SendspinFlacDecoder {
    FLAC__StreamDecoder* decoder;
    /* Input buffer state (set per decode call) */
    const uint8_t* input_buf;
    size_t input_len;
    size_t input_pos;
    /* Output buffer state (set per decode call) */
    int32_t* output_buf;
    size_t output_capacity;
    size_t output_pos;
    /* Whether the decoder has been initialized with a stream */
    int initialized;
    /* Set to 1 if the write callback aborted due to full output */
    int output_full;
};

static FLAC__StreamDecoderReadStatus read_cb(
    const FLAC__StreamDecoder* decoder,
    FLAC__byte buffer[],
    size_t* bytes,
    void* client_data)
{
    (void)decoder;
    SendspinFlacDecoder* ctx = (SendspinFlacDecoder*)client_data;
    size_t available = ctx->input_len - ctx->input_pos;
    if (available == 0) {
        *bytes = 0;
        return FLAC__STREAM_DECODER_READ_STATUS_END_OF_STREAM;
    }
    size_t to_read = *bytes < available ? *bytes : available;
    memcpy(buffer, ctx->input_buf + ctx->input_pos, to_read);
    ctx->input_pos += to_read;
    *bytes = to_read;
    return FLAC__STREAM_DECODER_READ_STATUS_CONTINUE;
}

static FLAC__StreamDecoderWriteStatus write_cb(
    const FLAC__StreamDecoder* decoder,
    const FLAC__Frame* frame,
    const FLAC__int32* const buffer[],
    void* client_data)
{
    (void)decoder;
    SendspinFlacDecoder* ctx = (SendspinFlacDecoder*)client_data;
    unsigned channels = frame->header.channels;
    unsigned blocksize = frame->header.blocksize;

    for (unsigned s = 0; s < blocksize; s++) {
        for (unsigned c = 0; c < channels; c++) {
            if (ctx->output_pos >= ctx->output_capacity) {
                ctx->output_full = 1;
                return FLAC__STREAM_DECODER_WRITE_STATUS_ABORT;
            }
            ctx->output_buf[ctx->output_pos++] = buffer[c][s];
        }
    }
    return FLAC__STREAM_DECODER_WRITE_STATUS_CONTINUE;
}

static void metadata_cb(
    const FLAC__StreamDecoder* decoder,
    const FLAC__StreamMetadata* metadata,
    void* client_data)
{
    (void)decoder;
    (void)metadata;
    (void)client_data;
    /* We don't need metadata; just consume it silently. */
}

static void error_cb(
    const FLAC__StreamDecoder* decoder,
    FLAC__StreamDecoderErrorStatus status,
    void* client_data)
{
    (void)decoder;
    (void)client_data;
    fprintf(stderr, "sendspin_flac: FLAC decode error: %s\n",
            FLAC__StreamDecoderErrorStatusString[status]);
}

SENDSPIN_FLAC_EXPORT SendspinFlacDecoder* sendspin_flac_new(void)
{
    SendspinFlacDecoder* ctx = (SendspinFlacDecoder*)calloc(1, sizeof(SendspinFlacDecoder));
    if (!ctx) return NULL;

    ctx->decoder = FLAC__stream_decoder_new();
    if (!ctx->decoder) {
        free(ctx);
        return NULL;
    }

    ctx->initialized = 0;
    return ctx;
}

static int ensure_initialized(SendspinFlacDecoder* ctx)
{
    if (ctx->initialized) return 1;

    FLAC__StreamDecoderInitStatus status = FLAC__stream_decoder_init_stream(
        ctx->decoder,
        read_cb,
        NULL, /* seek */
        NULL, /* tell */
        NULL, /* length */
        NULL, /* eof */
        write_cb,
        metadata_cb,
        error_cb,
        ctx
    );

    if (status != FLAC__STREAM_DECODER_INIT_STATUS_OK) {
        fprintf(stderr, "sendspin_flac: init failed: %s\n",
                FLAC__StreamDecoderInitStatusString[status]);
        return 0;
    }

    ctx->initialized = 1;
    return 1;
}

SENDSPIN_FLAC_EXPORT int sendspin_flac_decode(
    SendspinFlacDecoder* decoder,
    const uint8_t* input,
    size_t input_len,
    int32_t* output,
    size_t output_capacity)
{
    if (!decoder || !decoder->decoder) return -1;
    if (!input || input_len == 0) return 0;

    /* Set up input/output state for this decode call */
    decoder->input_buf = input;
    decoder->input_len = input_len;
    decoder->input_pos = 0;
    decoder->output_buf = output;
    decoder->output_capacity = output_capacity;
    decoder->output_pos = 0;
    decoder->output_full = 0;

    if (!ensure_initialized(decoder)) return -1;

    /* Process frames until input is consumed or output is full */
    while (decoder->input_pos < decoder->input_len && !decoder->output_full) {
        FLAC__bool ok = FLAC__stream_decoder_process_single(decoder->decoder);
        if (!ok && !decoder->output_full) {
            FLAC__StreamDecoderState state =
                FLAC__stream_decoder_get_state(decoder->decoder);
            if (state == FLAC__STREAM_DECODER_END_OF_STREAM) {
                break;
            }
            fprintf(stderr, "sendspin_flac: process_single failed, state=%s\n",
                    FLAC__StreamDecoderStateString[state]);
            /* If we produced some output, return it rather than erroring */
            if (decoder->output_pos > 0) break;
            return -1;
        }

        FLAC__StreamDecoderState state =
            FLAC__stream_decoder_get_state(decoder->decoder);
        if (state == FLAC__STREAM_DECODER_END_OF_STREAM) {
            break;
        }
    }

    return (int)decoder->output_pos;
}

SENDSPIN_FLAC_EXPORT void sendspin_flac_reset(SendspinFlacDecoder* decoder)
{
    if (!decoder || !decoder->decoder) return;

    if (decoder->initialized) {
        FLAC__stream_decoder_finish(decoder->decoder);
        decoder->initialized = 0;
    }

    decoder->input_buf = NULL;
    decoder->input_len = 0;
    decoder->input_pos = 0;
    decoder->output_buf = NULL;
    decoder->output_capacity = 0;
    decoder->output_pos = 0;
    decoder->output_full = 0;
}

SENDSPIN_FLAC_EXPORT void sendspin_flac_free(SendspinFlacDecoder* decoder)
{
    if (!decoder) return;

    if (decoder->decoder) {
        if (decoder->initialized) {
            FLAC__stream_decoder_finish(decoder->decoder);
        }
        FLAC__stream_decoder_delete(decoder->decoder);
    }

    free(decoder);
}
