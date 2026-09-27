/*
 * x100vi_helper.c - Standalone helper for X100VI preset slot access.
 *
 * Uses libusb to send PTP containers via bulk transfer.
 * Communicates via line-delimited JSON over stdin/stdout.
 *
 * Build the packaged macOS helper/runtime:
 *   ../scripts/build-macos-helper.sh --architectures arm64
 *
 * Run:
 *   echo '{"id":"1","command":"ping"}' | ./x100vi_helper
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdint.h>
#include <stdbool.h>
#include <limits.h>
#include <libusb-1.0/libusb.h>
#include <unistd.h>  /* for usleep */

#define FUJI_VENDOR       0x04CB
#define X100VI_PRODUCT    0x0305
/* The X100VI (firmware 1.31) accepts a D18D label of 0 to 25 printable ASCII
 * characters and rejects 26 or more with 0x201C, measured by write and
 * readback on C3. CameraPresetName.maximumCharacterCount is the same limit. */
#define FUJI_PRESET_NAME_MAX_CHARACTERS 25

/* ── PTP Property Definitions ─────────────────────────────────────────── */

typedef struct {
    uint16_t code;
    const char *name;
    const char *key;
    bool is_preset_slot;
} PropDef;

static const PropDef preset_props[] = {
    {0xD18C, "Preset Slot",           "slot",           true},
    {0xD18D, "Preset Name",           "name",           true},
    {0xD18E, "Image Size",            "image_size",     true},
    {0xD18F, "Image Quality",         "image_quality",  true},
    {0xD190, "Dynamic Range",         "dynamic_range",  true},
    {0xD191, "Unknown D191",          "unknown_d191",   true},
    {0xD192, "Film Simulation",       "film_simulation", true},
    {0xD193, "Mono Warm/Cool",        "mono_warm_cool", true},
    {0xD194, "Mono Mag/Green",        "mono_magenta_green", true},
    {0xD195, "Grain Effect",          "grain_effect",   true},
    {0xD196, "Color Chrome",          "color_chrome",   true},
    {0xD197, "Color Chrome FX Blue",  "color_chrome_fxb", true},
    {0xD198, "Smooth Skin",           "smooth_skin",    true},
    {0xD199, "White Balance",         "white_balance",  true},
    {0xD19A, "WB Shift Red",          "wb_shift_r",     true},
    {0xD19B, "WB Shift Blue",         "wb_shift_b",     true},
    {0xD19C, "Color Temp (K)",        "color_temp",     true},
    {0xD19D, "Highlight Tone",        "highlight",      true},
    {0xD19E, "Shadow Tone",           "shadow",         true},
    {0xD19F, "Color",                 "color",          true},
    {0xD1A0, "Sharpness",             "sharpness",      true},
    {0xD1A1, "High ISO NR",           "high_iso_nr",    true},
    {0xD1A2, "Clarity",               "clarity",        true},
    {0xD1A3, "Long Exp NR",           "long_exp_nr",    true},
    {0xD1A4, "Color Space",           "color_space",    true},
    {0xD1A5, "Unknown D1A5",          "unknown_d1a5",   true},
    {0, NULL, NULL, false}
};

static const PropDef active_props[] = {
    {0xD001, "Film Simulation",       "film_simulation",    false},
    {0xD007, "Dynamic Range",         "dynamic_range",      false},
    {0x5005, "White Balance",         "white_balance",      false},
    {0xD023, "Grain Effect",          "grain_effect",       false},
    {0xD002, "Color",                 "color",              false},
    {0xD00B, "WB Shift Red",          "wb_shift_r",         false},
    {0xD00C, "WB Shift Blue",         "wb_shift_b",         false},
    {0xD017, "Color Temperature",     "color_temp",         false},
    {0xD185, "Native Profile",        "native_profile",     false},
    {0xD20B, "Device Name",           "device_name",        false},
    {0xD242, "Battery Level",         "battery_level",      false},
    {0, NULL, NULL, false}
};

/* Fields exposed by PTPClientPresetData.  Preset properties are all sent as
 * 16-bit payloads; signed fields use Int16's two's-complement bit pattern. */
typedef struct {
    uint16_t code;
    const char *key;
    bool is_signed;
    bool conditional;
} PresetField;

static const PresetField preset_fields[] = {
    {0xD18E, "image_size",           false, false},
    {0xD18F, "image_quality",        false, false},
    {0xD190, "dynamic_range",        false, false},
    {0xD192, "film_simulation",      false, false},
    {0xD193, "mono_warm_cool",       true,  true},
    {0xD194, "mono_magenta_green",   true,  true},
    {0xD195, "grain_effect",         false, false},
    {0xD196, "color_chrome",         false, false},
    {0xD197, "color_chrome_fx_blue", false, false},
    {0xD198, "smooth_skin",          false, false},
    {0xD199, "white_balance",        false, false},
    {0xD19C, "color_temp",           false, true},
    {0xD19A, "wb_shift_r",           true,  false},
    {0xD19B, "wb_shift_b",           true,  false},
    {0xD19D, "highlight",            true,  false},
    {0xD19E, "shadow",               true,  false},
    {0xD19F, "color",                true,  false},
    {0xD1A0, "sharpness",            true,  false},
    {0xD1A1, "high_iso_nr",          false, false},
    {0xD1A2, "clarity",              true,  false},
    {0xD1A3, "long_exp_nr",          false, false},
    {0xD1A4, "color_space",          false, false},
    {0, NULL, false, false}
};

/* ── Value Resolution ─────────────────────────────────────────────────── */

static const char *r_film(uint32_t v) {
    static const char *n[] = {"","PROVIA","VELVIA","ASTIA","PRO_NEG_HI","PRO_NEG_STD",
        "MONOCHROME","MONO_Y","MONO_R","MONO_G","SEPIA","CLASSIC_CHROME","ACROS",
        "ACROS_Y","ACROS_R","ACROS_G","ETERNA","CLASSIC_NEG","ETERNA_BB","nostalgic_neg","reala_ace"};
    return (v>=1 && v<=20) ? n[v] : NULL;
}
static const char *r_dr(uint32_t v) {
    if (v==65535) return "AUTO";
    static const char *n[] = {"","100","200","400"};
    return (v>=100 && v<=400) ? n[v/100] : NULL;
}
static const char *r_grain(uint32_t v) {
    static const char *n[] = {"","OFF","WEAK_SMALL","STRONG_SMALL","WEAK_LARGE","STRONG_LARGE"};
    return (v >= 1 && v <= 5) ? n[v] : NULL;
}
static const char *r_chrome(uint32_t v) {
    static const char *n[] = {"OFF","WEAK","STRONG"};
    return (v<=2) ? n[v] : NULL;
}
static const char *r_wb(uint32_t v) {
    switch(v) {
        case 0: return "AS_SHOT"; case 2: return "AUTO"; case 4: return "DAYLIGHT";
        case 8: return "UNDERWATER"; case 32769: return "FL_1"; case 32770: return "FL_2";
        case 32771: return "FL_3"; case 32774: return "SHADE";
        case 32775: return "COLOR_TEMP"; case 32801: return "AMBIENCE";
    }
    return NULL;
}
static const char *resolve(const char *key, uint32_t v) {
    if (!strcmp(key,"film_simulation")) return r_film(v);
    if (!strcmp(key,"dynamic_range")) return r_dr(v);
    if (!strcmp(key,"grain_effect")) return r_grain(v);
    if (!strcmp(key,"color_chrome")||!strcmp(key,"color_chrome_fxb")||!strcmp(key,"smooth_skin"))
        return r_chrome(v);
    if (!strcmp(key,"white_balance")) return r_wb(v);
    return NULL;
}

/* ── JSON Helpers ─────────────────────────────────────────────────────── */

static void json_escape_string(FILE *f, const char *s) {
    fputc('"', f);
    while (*s) {
        switch (*s) {
            case '"': fputs("\\\"", f); break;
            case '\\': fputs("\\\\", f); break;
            case '\n': fputs("\\n", f); break;
            case '\r': fputs("\\r", f); break;
            case '\t': fputs("\\t", f); break;
            default: fputc(*s, f); break;
        }
        s++;
    }
    fputc('"', f);
}

/* ── PTP Container Operations ────────────────────────────────────────── */

/* Helper to write uint32 in little-endian */
static void put_u32_le(uint8_t *buf, uint32_t val) {
    buf[0] = val & 0xFF;
    buf[1] = (val >> 8) & 0xFF;
    buf[2] = (val >> 16) & 0xFF;
    buf[3] = (val >> 24) & 0xFF;
}

/* Helper to write uint16 in little-endian */
static void put_u16_le(uint8_t *buf, uint16_t val) {
    buf[0] = val & 0xFF;
    buf[1] = (val >> 8) & 0xFF;
}

/* Global transaction ID - starts at 0, increments per FilmKit/rawji */
static uint32_t g_transactionId = 0;
static bool g_sessionOpen = false;
/* The public connect result remains stable (-3 means session open failed), but
 * preserve the underlying libusb failure for the JSON client and hardware logs. */
static int g_lastSessionTransportError = 0;

static int ptp_send(libusb_device_handle *dev, uint16_t code, int paramCount, const uint32_t *params) {
    /* PTP Container: length(4) + type(2) + code(2) + trans_id(4) + params(N*4) */
    uint32_t totalLen = 12 + paramCount * 4;
    uint8_t buf[32];
    memset(buf, 0, sizeof(buf));
    put_u32_le(buf, totalLen);           /* [0-3] length */
    put_u16_le(buf + 4, 0x0001);         /* [4-5] type: Command (0x0001) */
    put_u16_le(buf + 6, code);           /* [6-7] operation code */
    put_u32_le(buf + 8, ++g_transactionId);  /* [8-11] transaction ID (incrementing) */
    for (int i = 0; i < paramCount && i < 5; i++) {
        put_u32_le(buf + 12 + i * 4, params[i]);
    }

    int transferred = 0;
    int rc = libusb_bulk_transfer(dev, 0x01, buf, (int)totalLen, &transferred, 5000);
    fprintf(stderr, "[DEBUG] ptp_send: code=0x%04X len=%u transferred=%d rc=%d\n", code, totalLen, transferred, rc);
    return rc;
}

/* Send a DATA container (type=0x0002) — NO params, just header + raw data */
static int ptp_send_data(libusb_device_handle *dev, uint16_t code,
                          uint32_t transactionId,
                          const uint8_t *data, uint32_t dataLen) {
    /* DATA container: 12-byte header + raw data (NO params) */
    uint32_t totalLen = 12 + dataLen;
    uint8_t header[12];
    put_u32_le(header, totalLen);
    put_u16_le(header + 4, 0x0002);  /* type: Data */
    put_u16_le(header + 6, code);
    put_u32_le(header + 8, transactionId);

    /* For small payloads, send header + data in one transfer */
    if (totalLen <= 65536) {  /* ≤ 64KB — fits in one transfer */
        uint8_t buf[65600];
        memcpy(buf, header, 12);
        if (dataLen > 0) memcpy(buf + 12, data, dataLen);
        int transferred = 0;
        int rc = libusb_bulk_transfer(dev, 0x01, buf, (int)totalLen, &transferred, 30000);
        fprintf(stderr, "[DEBUG] ptp_send_data: code=0x%04X len=%u transferred=%d rc=%d\n",
                code, totalLen, transferred, rc);
        return rc;
    }

    /* For large payloads (RAF files), send header+data chunked at 512KB
     * like FilmKit. The entire container is split across multiple USB
     * transfers but remains one logical PTP container. */
    const uint32_t chunkSize = 512 * 1024;
    uint32_t containerOffset = 0;  /* offset within the logical container */
    int chunkCount = 0;

    while (containerOffset < totalLen) {
        uint32_t remaining = totalLen - containerOffset;
        uint32_t thisChunk = remaining < chunkSize ? remaining : chunkSize;
        int transferred = 0;
        unsigned char *chunkPtr;
        int needFree = 0;

        /* First chunk: header + start of data */
        if (containerOffset == 0) {
            uint8_t *buf = (uint8_t *)malloc(thisChunk);
            if (!buf) return -99;
            memcpy(buf, header, 12);
            if (thisChunk > 12) memcpy(buf + 12, data, thisChunk - 12);
            chunkPtr = buf;
            needFree = 1;
        } else {
            /* Subsequent chunks: continue with data */
            chunkPtr = (unsigned char *)(data + (containerOffset - 12));
        }

        int rc = libusb_bulk_transfer(dev, 0x01, chunkPtr, (int)thisChunk, &transferred, 30000);
        if (needFree) free(chunkPtr);
        if (rc != LIBUSB_SUCCESS) {
            fprintf(stderr, "[DEBUG] ptp_send_data chunk %d: offset=%u/%u rc=%d\n",
                    chunkCount, containerOffset, totalLen, rc);
            return rc;
        }
        containerOffset += thisChunk;
        chunkCount++;
    }
    fprintf(stderr, "[DEBUG] ptp_send_data: code=0x%04X total=%u chunks=%d rc=0\n",
            code, totalLen, chunkCount);
    return LIBUSB_SUCCESS;
}

/* Send PTP container WITH data (deprecated - use ptp_send_data for vendor commands) */
static int ptp_send_with_data(libusb_device_handle *dev, uint16_t code,
                               int paramCount, const uint32_t *params,
                               const uint8_t *data, uint32_t dataLen) {
    uint8_t buf[256];
    memset(buf, 0, sizeof(buf));
    uint32_t headerLen = 12 + paramCount * 4;
    uint32_t totalLen = headerLen + dataLen;
    put_u32_le(buf, totalLen);
    put_u16_le(buf + 4, 0x0001);  /* type: Command */
    put_u16_le(buf + 6, code);
    put_u32_le(buf + 8, ++g_transactionId);
    for (int i = 0; i < paramCount && i < 5; i++) {
        put_u32_le(buf + 12 + i * 4, params[i]);
    }
    memcpy(buf + headerLen, data, dataLen);

    int transferred = 0;
    return libusb_bulk_transfer(dev, 0x01, buf, (int)(headerLen + dataLen), &transferred, 5000);
}

/* Forward declarations */
static int ptp_recv(libusb_device_handle *dev, uint8_t *resp, int maxlen, int *outlen);
static int write_prop(libusb_device_handle *dev, uint16_t prop, uint8_t *data, uint32_t dataLen);
static int ptp_send_data(libusb_device_handle *dev, uint16_t code,
                          uint32_t transactionId,
                          const uint8_t *data, uint32_t dataLen);

/* Send COMMAND only (no DATA), receive RESPONSE */
static int send_command_only(libusb_device_handle *dev, uint16_t code,
                             int paramCount, const uint32_t *params) {
    uint8_t resp[64]; int len = 0;

    /* Send COMMAND */
    int rc = ptp_send(dev, code, paramCount, params);
    if (rc != LIBUSB_SUCCESS) return rc;

    /* Receive RESPONSE */
    rc = ptp_recv(dev, resp, sizeof(resp), &len);
    if (rc != LIBUSB_SUCCESS) return rc;
    if (len < 8) return -2;

    uint16_t type = resp[4] | (resp[5] << 8);
    uint16_t respCode = resp[6] | (resp[7] << 8);
    fprintf(stderr, "[DEBUG] send_command_only: type=0x%04X code=0x%04X\n", type, respCode);
    if (type != 0x0003) return -3;

    return (respCode == 0x2001) ? 0 : -4;
}

/* Clear endpoint halt (stall) — recovers from LIBUSB_ERROR_PIPE */
static int clear_endpoint_halt(libusb_device_handle *dev, uint8_t endpoint) {
    int rc = libusb_clear_halt(dev, endpoint);
    fprintf(stderr, "[DEBUG] clear_endpoint_halt: ep=0x%02X rc=%d\n", endpoint, rc);
    return rc;
}

/* Send vendor command with data — proper 3-phase PTP (COMMAND, DATA, RESPONSE)
 *
 * KEY DIFFERENCE from standard PTP:
 * - COMMAND and DATA are sent as SEPARATE USB transfers (like FilmKit/rawji)
 * - DATA container has NO params — 12-byte header + raw data only
 * - Large data is chunked (64KB per chunk)
 * - Includes stall recovery for robustness
 *
 * This matches the protocol used by FilmKit (WebUSB) and rawji (PyUSB).
 */
static int send_vendor_command(libusb_device_handle *dev, uint16_t code,
                                int cmdParamCount, const uint32_t *cmdParams,
                                const uint8_t *data, uint32_t dataLen,
                                int timeoutMs) {
    uint8_t resp[64]; int len = 0;
    uint32_t transId = ++g_transactionId;
    int rc;

    fprintf(stderr, "[VENDOR] command=0x%04X transId=%u params=%d data=%u timeout=%dms\n",
            code, transId, cmdParamCount, dataLen, timeoutMs);

    /* Phase 1: Send COMMAND container (type=0x0001, with params) */
    uint32_t cmdLen = 12 + cmdParamCount * 4;
    uint8_t cmdBuf[32];
    memset(cmdBuf, 0, sizeof(cmdBuf));
    put_u32_le(cmdBuf, cmdLen);
    put_u16_le(cmdBuf + 4, 0x0001);  /* type: Command */
    put_u16_le(cmdBuf + 6, code);
    put_u32_le(cmdBuf + 8, transId);
    for (int i = 0; i < cmdParamCount && i < 5; i++) {
        put_u32_le(cmdBuf + 12 + i * 4, cmdParams[i]);
    }

    int transferred = 0;
    rc = libusb_bulk_transfer(dev, 0x01, cmdBuf, (int)cmdLen, &transferred, timeoutMs);
    fprintf(stderr, "[VENDOR] CMD sent: len=%u transferred=%d rc=%d\n", cmdLen, transferred, rc);
    if (rc == LIBUSB_ERROR_PIPE) {
        fprintf(stderr, "[VENDOR] CMD endpoint stalled, clearing halt...\n");
        clear_endpoint_halt(dev, 0x01);
        /* Small delay after clearing halt */
        usleep(100000);  /* 100ms */
        return -100;  /* Signal stall */
    }
    if (rc != LIBUSB_SUCCESS) {
        fprintf(stderr, "[VENDOR] CMD failed: rc=%d\n", rc);
        return rc;
    }

    /* Phase 2: Send DATA container (type=0x0002, NO params, raw data only) */
    /* This matches FilmKit/rawji: DATA container = 12-byte header + data, no params */
    rc = ptp_send_data(dev, code, transId, data, dataLen);
    if (rc == LIBUSB_ERROR_PIPE) {
        fprintf(stderr, "[VENDOR] DATA endpoint stalled, clearing halt...\n");
        clear_endpoint_halt(dev, 0x01);
        usleep(100000);
        return -100;  /* Signal stall */
    }
    if (rc != LIBUSB_SUCCESS) {
        fprintf(stderr, "[VENDOR] DATA failed: rc=%d\n", rc);
        return rc;
    }

    /* Phase 3: Receive RESPONSE container (type=0x0003) */
    /* Small delay before reading response (camera needs to process) */
    usleep(10000);  /* 10ms */
    rc = ptp_recv(dev, resp, sizeof(resp), &len);
    if (rc == LIBUSB_ERROR_PIPE) {
        fprintf(stderr, "[VENDOR] RESP endpoint stalled, clearing halt...\n");
        clear_endpoint_halt(dev, 0x81);
        usleep(200000);  /* 200ms settle after clear */
        /* Retry once after clearing halt — macOS libusb commonly stalls */
        rc = ptp_recv(dev, resp, sizeof(resp), &len);
        if (rc == LIBUSB_ERROR_PIPE) {
            fprintf(stderr, "[VENDOR] RESP still stalled after retry, giving up\n");
            return -101;  /* Signal IN stall */
        }
    }
    if (rc != LIBUSB_SUCCESS) {
        fprintf(stderr, "[VENDOR] RESP recv failed: rc=%d len=%d\n", rc, len);
        return rc;
    }
    if (len < 12) {
        fprintf(stderr, "[VENDOR] RESP too short: %d bytes\n", len);
        return -2;
    }

    uint16_t type = resp[4] | (resp[5] << 8);
    uint16_t respCode = resp[6] | (resp[7] << 8);
    fprintf(stderr, "[VENDOR] RESP: type=0x%04X code=0x%04X len=%d\n", type, respCode, len);
    if (type != 0x0003) {
        fprintf(stderr, "[VENDOR] Expected RESPONSE, got type 0x%04X\n", type);
        return -3;
    }
    if (respCode != 0x2001) {
        fprintf(stderr, "[VENDOR] Response code 0x%04X (not OK 0x2001)\n", respCode);
    }
    return (respCode == 0x2001) ? 0 : (int)respCode;
}

/* Send COMMAND + DATA (COMBINED in single transfer), receive RESPONSE
 * DEPRECATED — use send_vendor_command for Fuji vendor operations */
static int send_two_phase_combined(libusb_device_handle *dev, uint16_t code,
                                   int paramCount, const uint32_t *params,
                                   const uint8_t *data, uint32_t dataLen) {
    uint8_t resp[64]; int len = 0;
    uint8_t combined[1024];
    uint32_t cmdHeaderLen = 12 + paramCount * 4;

    /* Build COMMAND */
    put_u32_le(combined, cmdHeaderLen);
    put_u16_le(combined + 4, 0x0001);
    put_u16_le(combined + 6, code);
    uint32_t transId = ++g_transactionId;
    put_u32_le(combined + 8, transId);
    for (int i = 0; i < paramCount && i < 5; i++) {
        put_u32_le(combined + 12 + i * 4, params[i]);
    }

    /* Build DATA (same transId) */
    uint32_t dataHeaderLen = 12 + paramCount * 4;
    uint32_t dataTotalLen = dataHeaderLen + dataLen;
    uint32_t offset = cmdHeaderLen;
    put_u32_le(combined + offset, dataTotalLen); offset += 4;
    put_u16_le(combined + offset, 0x0002); offset += 2;
    put_u16_le(combined + offset, code); offset += 2;
    put_u32_le(combined + offset, transId); offset += 4;
    memcpy(combined + offset, data, dataLen);

    uint32_t totalLen = offset + dataLen;
    int transferred = 0;
    fprintf(stderr, "[DEBUG] send_two_phase_combined: %u bytes total\n", totalLen);
    int rc = libusb_bulk_transfer(dev, 0x01, combined, (int)totalLen, &transferred, 5000);
    fprintf(stderr, "[DEBUG] send_two_phase_combined sent: rc=%d transferred=%d\n", rc, transferred);
    if (rc != LIBUSB_SUCCESS) return rc;

    /* RESPONSE */
    rc = ptp_recv(dev, resp, sizeof(resp), &len);
    if (rc != LIBUSB_SUCCESS) return rc;
    if (len < 8) return -2;
    uint16_t type = resp[4] | (resp[5] << 8);
    uint16_t respCode = resp[6] | (resp[7] << 8);
    fprintf(stderr, "[DEBUG] send_two_phase_combined RESP: type=0x%04X code=0x%04X\n", type, respCode);
    if (type != 0x0003) return -3;
    return (respCode == 0x2001) ? 0 : -4;
}

/* Send OBJECT_INFO to camera (Fuji vendor command 0x900C) */
/* Vendor command functions - DISABLED (cause device stall) */
/* static int send_object_info(...) { ... } */
/* static int send_object_data(...) { ... } */

#define PTP_HEADER_LENGTH 12u
#define PTP_MAX_CONTAINER_LENGTH (256u * 1024u * 1024u)

enum {
    PTP_FRAME_INVALID_LENGTH = -1000,
    PTP_FRAME_INVALID_TYPE = -1001,
    PTP_FRAME_INVALID_CODE = -1002,
    PTP_FRAME_INVALID_TRANSACTION = -1003,
    PTP_FRAME_SHORT_READ = -1004,
    PTP_FRAME_ALLOCATION_FAILED = -1005,
};

typedef int (*PtpReadFunction)(void *context, uint8_t *buffer, size_t length,
                               size_t *transferred);

typedef struct {
    uint32_t length;
    uint16_t type;
    uint16_t code;
    uint32_t transactionId;
    uint8_t *payload;
    uint32_t payloadLength;
} PtpContainer;

static uint16_t get_u16_le(const uint8_t *buf) {
    return (uint16_t)(buf[0] | ((uint16_t)buf[1] << 8));
}

static uint32_t get_u32_le(const uint8_t *buf) {
    return (uint32_t)buf[0] | ((uint32_t)buf[1] << 8) |
           ((uint32_t)buf[2] << 16) | ((uint32_t)buf[3] << 24);
}

static void ptp_container_free(PtpContainer *container) {
    free(container->payload);
    memset(container, 0, sizeof(*container));
}

/* Fixture reader used by framing tests. The live libusb reader below keeps an
 * inbound buffer because USB bulk transfers do not preserve PTP container
 * boundaries. */
static int ptp_read_container_with(PtpReadFunction readFunction, void *context,
                                   PtpContainer *container) {
    uint8_t header[PTP_HEADER_LENGTH];
    size_t offset = 0;
    memset(container, 0, sizeof(*container));

    while (offset < sizeof(header)) {
        size_t transferred = 0;
        int rc = readFunction(context, header + offset, sizeof(header) - offset,
                              &transferred);
        if (rc != LIBUSB_SUCCESS) return rc;
        if (transferred == 0) return PTP_FRAME_SHORT_READ;
        offset += transferred;
    }

    container->length = get_u32_le(header);
    container->type = get_u16_le(header + 4);
    container->code = get_u16_le(header + 6);
    container->transactionId = get_u32_le(header + 8);
    if (container->length < PTP_HEADER_LENGTH ||
        container->length > PTP_MAX_CONTAINER_LENGTH) {
        return PTP_FRAME_INVALID_LENGTH;
    }

    container->payloadLength = container->length - PTP_HEADER_LENGTH;
    if (container->payloadLength == 0) return LIBUSB_SUCCESS;
    container->payload = malloc(container->payloadLength);
    if (!container->payload) return PTP_FRAME_ALLOCATION_FAILED;

    offset = 0;
    while (offset < container->payloadLength) {
        size_t transferred = 0;
        int rc = readFunction(context, container->payload + offset,
                              container->payloadLength - offset, &transferred);
        if (rc != LIBUSB_SUCCESS) {
            ptp_container_free(container);
            return rc;
        }
        if (transferred == 0) {
            ptp_container_free(container);
            return PTP_FRAME_SHORT_READ;
        }
        offset += transferred;
    }
    return LIBUSB_SUCCESS;
}

/* A property DATA container can be 14 bytes while the PTP header is 12 bytes.
 * Asking libusb for exactly 12 causes macOS to report LIBUSB_ERROR_OVERFLOW and
 * discard the two-byte payload. Retain every byte supplied by a generous bulk
 * read so a following RESPONSE container is not lost when both arrive together. */
#define PTP_RX_BUFFER_CAPACITY (64 * 1024)
static uint8_t g_ptpRxBuffer[PTP_RX_BUFFER_CAPACITY];
static size_t g_ptpRxLength = 0;

static void ptp_reset_receive_buffer(void) {
    g_ptpRxLength = 0;
}

/* A USB handle can be released while the camera still owns a PTP session.
 * Always reset both halves of our local transport state together so a new
 * connection starts with OpenSession transaction ID 1 and no stale bytes. */
static void ptp_reset_transport_state(void) {
    g_sessionOpen = false;
    g_transactionId = 0;
    ptp_reset_receive_buffer();
}

static int ptp_read_exact(libusb_device_handle *dev, uint8_t *output, size_t length) {
    size_t offset = 0;
    while (offset < length) {
        if (g_ptpRxLength == 0) {
            int actual = 0;
            int rc = libusb_bulk_transfer(dev, 0x81, g_ptpRxBuffer,
                                          (int)sizeof(g_ptpRxBuffer), &actual, 10000);
            if (rc != LIBUSB_SUCCESS) return rc;
            if (actual <= 0) return PTP_FRAME_SHORT_READ;
            g_ptpRxLength = (size_t)actual;
        }

        size_t available = length - offset;
        size_t count = g_ptpRxLength < available ? g_ptpRxLength : available;
        memcpy(output + offset, g_ptpRxBuffer, count);
        offset += count;
        g_ptpRxLength -= count;
        if (g_ptpRxLength > 0) {
            memmove(g_ptpRxBuffer, g_ptpRxBuffer + count, g_ptpRxLength);
        }
    }
    return LIBUSB_SUCCESS;
}

static int ptp_read_container(libusb_device_handle *dev, PtpContainer *container) {
    uint8_t header[PTP_HEADER_LENGTH];
    memset(container, 0, sizeof(*container));

    int rc = ptp_read_exact(dev, header, sizeof(header));
    if (rc != LIBUSB_SUCCESS) return rc;

    container->length = get_u32_le(header);
    container->type = get_u16_le(header + 4);
    container->code = get_u16_le(header + 6);
    container->transactionId = get_u32_le(header + 8);
    if (container->length < PTP_HEADER_LENGTH ||
        container->length > PTP_MAX_CONTAINER_LENGTH) {
        return PTP_FRAME_INVALID_LENGTH;
    }

    container->payloadLength = container->length - PTP_HEADER_LENGTH;
    if (container->payloadLength == 0) return LIBUSB_SUCCESS;
    container->payload = malloc(container->payloadLength);
    if (!container->payload) return PTP_FRAME_ALLOCATION_FAILED;

    rc = ptp_read_exact(dev, container->payload, container->payloadLength);
    if (rc != LIBUSB_SUCCESS) {
        ptp_container_free(container);
        return rc;
    }
    return LIBUSB_SUCCESS;
}

static int ptp_validate_container(const PtpContainer *container,
                                  uint16_t expectedType, uint16_t expectedCode,
                                  uint32_t expectedTransactionId) {
    if (container->type != expectedType) return PTP_FRAME_INVALID_TYPE;
    if (container->code != expectedCode) return PTP_FRAME_INVALID_CODE;
    if (container->transactionId != expectedTransactionId) {
        return PTP_FRAME_INVALID_TRANSACTION;
    }
    return LIBUSB_SUCCESS;
}

/* OpenSession and CloseSession are deliberately handled outside the generic
 * control helpers: their response container is part of connection lifecycle
 * correctness.  In particular, never accept a response for a different
 * transaction after a reconnect. */
static int ptp_send_session_command(libusb_device_handle *dev, uint16_t operationCode,
                                    bool hasSessionId, uint16_t *responseCode) {
    const uint32_t transactionId = ++g_transactionId;
    const uint32_t commandLength = 12 + (hasSessionId ? 4 : 0);
    uint8_t command[16] = {0};
    put_u32_le(command, commandLength);
    put_u16_le(command + 4, 0x0001);
    put_u16_le(command + 6, operationCode);
    put_u32_le(command + 8, transactionId);
    if (hasSessionId) put_u32_le(command + 12, 1);

    int transferred = 0;
    int rc = libusb_bulk_transfer(dev, 0x01, command, (int)commandLength,
                                  &transferred, 5000);
    if (rc != LIBUSB_SUCCESS || transferred != (int)commandLength) {
        fprintf(stderr,
                "[SESSION] 0x%04X command failed: rc=%d transferred=%d expected=%u tx=%u\n",
                operationCode, rc, transferred, commandLength, transactionId);
        return rc == LIBUSB_SUCCESS ? PTP_FRAME_SHORT_READ : rc;
    }

    PtpContainer response;
    rc = ptp_read_container(dev, &response);
    if (rc != LIBUSB_SUCCESS) {
        fprintf(stderr, "[SESSION] 0x%04X response read failed: rc=%d tx=%u\n",
                operationCode, rc, transactionId);
        return rc;
    }

    const int validation = ptp_validate_container(&response, 0x0003,
                                                   response.code, transactionId);
    if (validation != LIBUSB_SUCCESS) {
        fprintf(stderr,
                "[SESSION] 0x%04X invalid response: type=0x%04X code=0x%04X tx=%u "
                "(expected type=0x0003 tx=%u, validation=%d)\n",
                operationCode, response.type, response.code, response.transactionId,
                transactionId, validation);
        ptp_container_free(&response);
        return validation;
    }

    *responseCode = response.code;
    fprintf(stderr, "[SESSION] 0x%04X response: type=0x%04X code=0x%04X tx=%u\n",
            operationCode, response.type, response.code, response.transactionId);
    ptp_container_free(&response);
    return LIBUSB_SUCCESS;
}

static int ptp_parse_object_handles(const PtpContainer *data,
                                    const uint8_t **handles,
                                    uint32_t *handleCount) {
    if (data->payloadLength < 4) return PTP_FRAME_INVALID_LENGTH;
    uint32_t count = get_u32_le(data->payload);
    if (count > (data->payloadLength - 4) / 4) return PTP_FRAME_INVALID_LENGTH;
    *handles = data->payload + 4;
    *handleCount = count;
    return LIBUSB_SUCCESS;
}

static int ptp_read_data_and_ok_response(libusb_device_handle *dev,
                                         uint16_t operationCode,
                                         uint32_t transactionId,
                                         PtpContainer *data) {
    int rc = ptp_read_container(dev, data);
    if (rc != LIBUSB_SUCCESS) return rc;
    rc = ptp_validate_container(data, 0x0002, operationCode, transactionId);
    if (rc != LIBUSB_SUCCESS) {
        ptp_container_free(data);
        return rc;
    }

    PtpContainer response;
    rc = ptp_read_container(dev, &response);
    if (rc != LIBUSB_SUCCESS) {
        ptp_container_free(data);
        return rc;
    }
    rc = ptp_validate_container(&response, 0x0003, 0x2001, transactionId);
    ptp_container_free(&response);
    if (rc != LIBUSB_SUCCESS) {
        ptp_container_free(data);
        return rc;
    }
    return LIBUSB_SUCCESS;
}

/* Compatibility wrapper for existing small control paths.  Unlike the old
 * implementation, it never treats an incomplete USB transfer as a container. */
static int ptp_recv(libusb_device_handle *dev, uint8_t *resp, int maxlen, int *outlen) {
    PtpContainer container;
    int rc = ptp_read_container(dev, &container);
    if (rc != LIBUSB_SUCCESS) return rc;
    if (container.length > (uint32_t)maxlen) {
        ptp_container_free(&container);
        return PTP_FRAME_INVALID_LENGTH;
    }
    put_u32_le(resp, container.length);
    put_u16_le(resp + 4, container.type);
    put_u16_le(resp + 6, container.code);
    put_u32_le(resp + 8, container.transactionId);
    if (container.payloadLength > 0) {
        memcpy(resp + PTP_HEADER_LENGTH, container.payload, container.payloadLength);
    }
    *outlen = (int)container.length;
    ptp_container_free(&container);
    return LIBUSB_SUCCESS;
}

/* Read a device-property payload and require the following PTP response. */
static int read_prop_payload(libusb_device_handle *dev, uint16_t prop,
                             uint8_t *payload, uint32_t payloadCapacity,
                             uint32_t *payloadLen) {
    uint8_t buf[256]; int len = 0;

    /* GetDevicePropValue: 0x1015 */
    uint32_t params[] = {prop};
    int rc = ptp_send(dev, 0x1015, 1, params);
    if (rc != LIBUSB_SUCCESS) return rc;

    /* Step 1: Receive DATA container (type=0x0002) with property value */
    rc = ptp_recv(dev, buf, sizeof(buf), &len);
    fprintf(stderr, "[DEBUG] read_prop DATA recv: rc=%d len=%d\n", rc, len);
    if (rc != LIBUSB_SUCCESS || len < 12) return -2;
    
    uint16_t dataType = buf[4] | (buf[5] << 8);
    uint16_t dataCode = buf[6] | (buf[7] << 8);
    fprintf(stderr, "[DEBUG] DATA type=0x%04X code=0x%04X\n", dataType, dataCode);
    if (dataType != 0x0002) return -3;  /* Expected DATA container */
    
    uint32_t dataLen = (len > 12) ? (uint32_t)(len - 12) : 0;
    if (dataLen > payloadCapacity) return -7;
    if (dataLen > 0) memcpy(payload, buf + 12, dataLen);
    *payloadLen = dataLen;

    /* Step 2: Receive RESPONSE container (type=0x0003) */
    rc = ptp_recv(dev, buf, sizeof(buf), &len);
    fprintf(stderr, "[DEBUG] read_prop RESP recv: rc=%d len=%d\n", rc, len);
    if (rc != LIBUSB_SUCCESS || len < 12) return -4;
    
    uint16_t respType = buf[4] | (buf[5] << 8);
    uint16_t respCode = buf[6] | (buf[7] << 8);
    fprintf(stderr, "[DEBUG] RESP type=0x%04X code=0x%04X\n", respType, respCode);
    
    if (respType != 0x0003) return -5;
    return (respCode == 0x2001) ? 0 : (int)respCode;
}

/* Read a scalar device property.  Fuji C-slot numeric properties are 16-bit,
 * but this helper retains support for the few 1- and 4-byte properties. */
static int read_prop(libusb_device_handle *dev, uint16_t prop, uint32_t *val) {
    uint8_t payload[4] = {0};
    uint32_t payloadLen = 0;
    int rc = read_prop_payload(dev, prop, payload, sizeof(payload), &payloadLen);
    if (rc != 0) return rc;

    *val = 0;
    if (payloadLen >= 4) {
        *val = payload[0] | (payload[1] << 8) | (payload[2] << 16) | (payload[3] << 24);
    } else if (payloadLen == 2) {
        *val = payload[0] | (payload[1] << 8);
    } else if (payloadLen == 1) {
        *val = payload[0];
    }
    fprintf(stderr, "[DEBUG] property value=0x%08X (payloadLen=%u)\n", *val, payloadLen);
    return 0;
}

/* Read a large device property and save to file (e.g., 0xD185 native profile ~625 bytes) */
static int read_large_prop(libusb_device_handle *dev, uint16_t prop, const char *filePath) {
    uint32_t params[] = {prop};

    /* Send GetDevicePropValue */
    int rc = ptp_send(dev, 0x1015, 1, params);
    if (rc != LIBUSB_SUCCESS) return rc;
    uint32_t transactionId = g_transactionId;
    PtpContainer data;
    rc = ptp_read_data_and_ok_response(dev, 0x1015, transactionId, &data);
    if (rc != LIBUSB_SUCCESS) return rc;

    fprintf(stderr, "[LARGE_PROP] Property 0x%04X: %u bytes → %s\n",
            prop, data.payloadLength, filePath);
    FILE *f = fopen(filePath, "wb");
    if (!f) {
        ptp_container_free(&data);
        return -98;
    }
    size_t written = fwrite(data.payload, 1, data.payloadLength, f);
    fclose(f);
    if (written != data.payloadLength) {
        ptp_container_free(&data);
        return -98;
    }
    uint32_t dataLen = data.payloadLength;
    ptp_container_free(&data);

    fprintf(stderr, "[LARGE_PROP] Written %u bytes to %s\n", dataLen, filePath);
    return 0;
}

/* Trigger RAW conversion by setting property 0xD183 */
/*
 * X100VI protocol (per FilmKit, tested on X100VI):
 *   value=0 triggers conversion (both preview and full)
 *   FilmKit always sends 0 regardless of resolution setting
 *   rawji (Linux, X-T30/X-T4) uses 1=full, 0=preview — different behavior
 *
 * For X100VI compatibility, we always send 0 to match FilmKit exactly.
 */

/* Build and send a default d185 profile to the camera.
 * Required before triggering — camera needs conversion parameters.
 * FilmKit/rawji read from camera and write back. On macOS we can't read
 * after upload (IN endpoint broken), so we build from scratch.
 * Based on rawji's fuji_profile.py standard format (632 bytes). */
static int send_default_profile(libusb_device_handle *dev) {
    uint8_t profile[632];
    memset(profile, 0, sizeof(profile));

    /* Header: n_props = 29 */
    put_u16_le(profile, 29);

    /* IOPCode for X100VI (X-Processor 5): "FF179502" */
    const char *iocode = "FF179502";
    profile[2] = (uint8_t)(strlen(iocode) + 1);
    for (int i = 0; i < (int)strlen(iocode); i++) {
        put_u16_le(profile + 3 + i * 2, (uint16_t)iocode[i]);
    }

    /* 29 params at offset 0x201 (513) — defaults from rawji */
    int off = 0x201;
    put_u32_le(profile + off, 0x2); off += 4; /* ShootingCondition */
    put_u32_le(profile + off, 0x7); off += 4; /* FileType */
    put_u32_le(profile + off, 0x7); off += 4; /* ImageSize L 3:2 */
    put_u32_le(profile + off, 0x2); off += 4; /* ImageQuality Fine */
    put_u32_le(profile + off, 0); off += 4;   /* ExposureBias */
    put_u32_le(profile + off, 0x1); off += 4; /* DynamicRange DR100 */
    put_u32_le(profile + off, 0); off += 4;   /* WideDRange */
    put_u32_le(profile + off, 0x1); off += 4; /* FilmSimulation Provia */
    put_u32_le(profile + off, 0); off += 4;   /* GrainEffect */
    put_u32_le(profile + off, 0); off += 4;   /* ColorChromeEffect */
    put_u32_le(profile + off, 0); off += 4;   /* WBShootCond */
    put_u32_le(profile + off, 0); off += 4;   /* WhiteBalance AsShot */
    put_u32_le(profile + off, 0); off += 4;   /* WBShiftR */
    put_u32_le(profile + off, 0); off += 4;   /* WBShiftB */
    put_u32_le(profile + off, 0); off += 4;   /* WBColorTemp */
    put_u32_le(profile + off, 0); off += 4;   /* HighlightTone */
    put_u32_le(profile + off, 0); off += 4;   /* ShadowTone */
    put_u32_le(profile + off, 0); off += 4;   /* Color */
    put_u32_le(profile + off, 0); off += 4;   /* Sharpness */
    put_u32_le(profile + off, 0); off += 4;   /* NoiseReduction */
    put_u32_le(profile + off, 0); off += 4;   /* Reserved20 */
    put_u32_le(profile + off, 0); off += 4;   /* ColorSpace */
    put_u32_le(profile + off, 0); off += 4;   /* HDR */
    put_u32_le(profile + off, 0); off += 4;   /* SmoothSkinEffect */
    put_u32_le(profile + off, 0); off += 4;   /* ColorChromeBlue */
    put_u32_le(profile + off, 0); off += 4;   /* Reserved25 */
    put_u32_le(profile + off, 0); off += 4;   /* Clarity */
    put_u32_le(profile + off, 0); off += 4;   /* Reserved27 */
    put_u32_le(profile + off, 0); off += 4;   /* Reserved28 */

    fprintf(stderr, "[PROFILE] Sending default d185 profile (%d bytes, IOPCode=%s)...\n", (int)sizeof(profile), iocode);

    uint32_t setParam[] = {0xD185};
    int rc = ptp_send(dev, 0x1016, 1, setParam);
    if (rc != LIBUSB_SUCCESS) { fprintf(stderr, "[PROFILE] CMD failed: rc=%d\n", rc); return rc; }
    rc = ptp_send_data(dev, 0x1016, g_transactionId, profile, sizeof(profile));
    if (rc != LIBUSB_SUCCESS) { fprintf(stderr, "[PROFILE] DATA failed: rc=%d\n", rc); return rc; }
    uint8_t resp[32]; int rlen = 0;
    usleep(10000);
    rc = ptp_recv(dev, resp, sizeof(resp), &rlen);
    if (rc != LIBUSB_SUCCESS || rlen < 12) { fprintf(stderr, "[PROFILE] RESP failed: rc=%d len=%d\n", rc, rlen); return rc; }
    uint16_t respCode = resp[6] | (resp[7] << 8);
    fprintf(stderr, "[PROFILE] Response: 0x%04X\n", respCode);
    return (respCode == 0x2001) ? 0 : -1;
}

static int trigger_conversion(libusb_device_handle *dev) {
    uint8_t data[2];
    put_u16_le(data, 0);  /* Always 0 — matches FilmKit (X100VI tested) */
    fprintf(stderr, "[CONVERT] Triggering conversion (value=0, FilmKit protocol)...\n");
    int rc = write_prop(dev, 0xD183, data, 2);
    if (rc == 0) {
        fprintf(stderr, "[CONVERT] Conversion started\n");
    } else {
        fprintf(stderr, "[CONVERT] Failed: rc=%d\n", rc);
    }
    return rc;
}

/* Conversion retrieval is deliberately evidence-based.  A camera can expose
 * existing card objects through GetObjectHandles, so the first returned handle
 * is never assumed to be a conversion result and is never deleted. */
typedef struct {
    uint32_t *handles;
    uint32_t count;
} ObjectInventory;

typedef struct {
    int rc;
    const char *state;
    uint32_t baseline_count, post_count, new_count, inspected_count;
    uint32_t candidate_handle, candidate_format, candidate_size;
    char candidate_name[128];
    bool downloaded;
} ConversionRetrieval;

static ObjectInventory g_conversion_baseline = {NULL, 0};
/* A successful empty inventory is valid: `handles` remains NULL when count is
 * zero, so pointer presence cannot distinguish it from no pre-trigger scan. */
static bool g_conversion_baseline_captured = false;

static void inventory_free(ObjectInventory *inventory) {
    free(inventory->handles);
    inventory->handles = NULL;
    inventory->count = 0;
}

static bool inventory_contains(const ObjectInventory *inventory, uint32_t handle) {
    for (uint32_t i = 0; i < inventory->count; i++)
        if (inventory->handles[i] == handle) return true;
    return false;
}

static int inventory_append(ObjectInventory *inventory, uint32_t handle) {
    if (inventory_contains(inventory, handle)) return 0;
    uint32_t *handles = realloc(inventory->handles, (inventory->count + 1) * sizeof(*handles));
    if (!handles) return -99;
    inventory->handles = handles;
    inventory->handles[inventory->count++] = handle;
    return 0;
}

static int inventory_for_storage(libusb_device_handle *dev, uint32_t storageID,
                                 ObjectInventory *inventory) {
    uint32_t params[] = {storageID, 0x0000, 0x00000000};
    int rc = ptp_send(dev, 0x1007, 3, params); /* GetObjectHandles */
    if (rc != LIBUSB_SUCCESS) return rc;
    PtpContainer data;
    rc = ptp_read_data_and_ok_response(dev, 0x1007, g_transactionId, &data);
    if (rc != LIBUSB_SUCCESS) return rc;
    const uint8_t *handles = NULL; uint32_t count = 0;
    rc = ptp_parse_object_handles(&data, &handles, &count);
    if (rc == LIBUSB_SUCCESS) {
        for (uint32_t i = 0; i < count && rc == LIBUSB_SUCCESS; i++)
            rc = inventory_append(inventory, get_u32_le(handles + (i * 4)));
    }
    ptp_container_free(&data);
    return rc;
}

/* GetStorageIDs is opportunistic: querying all storage remains a documented
 * fallback for cameras which do not implement it in this USB mode. */
static int capture_object_inventory(libusb_device_handle *dev, ObjectInventory *inventory) {
    inventory_free(inventory);
    int rc = ptp_send(dev, 0x1004, 0, NULL); /* GetStorageIDs */
    if (rc == LIBUSB_SUCCESS) {
        PtpContainer data;
        rc = ptp_read_data_and_ok_response(dev, 0x1004, g_transactionId, &data);
        if (rc == LIBUSB_SUCCESS && data.payloadLength >= 4) {
            uint32_t count = get_u32_le(data.payload);
            if (count <= (data.payloadLength - 4) / 4) {
                for (uint32_t i = 0; i < count && rc == LIBUSB_SUCCESS; i++)
                    rc = inventory_for_storage(dev, get_u32_le(data.payload + 4 + i * 4), inventory);
            } else rc = PTP_FRAME_INVALID_LENGTH;
        }
        ptp_container_free(&data);
        if (rc == LIBUSB_SUCCESS) return 0;
        inventory_free(inventory);
    }
    return inventory_for_storage(dev, 0xFFFFFFFF, inventory);
}

static int ptp_string_to_ascii(const uint8_t *data, uint32_t available,
                               char *out, size_t outSize) {
    if (available < 1 || outSize == 0) return -1;
    uint32_t units = data[0];
    if (units == 0) { out[0] = '\0'; return 1; }
    if (1 + units * 2 > available) return -1;
    size_t n = 0;
    for (uint32_t i = 0; i + 1 < units && n + 1 < outSize; i++) {
        uint16_t ch = get_u16_le(data + 1 + i * 2);
        /* Keep this field safe for the line-delimited JSON response. */
        out[n++] = (ch >= 0x20 && ch <= 0x7E && ch != '"' && ch != '\\')
            ? (char)ch : '?';
    }
    out[n] = '\0';
    return 1 + units * 2;
}

static bool object_info_is_jpeg(const uint8_t *payload, uint32_t length,
                                uint16_t *format, uint32_t *size,
                                char *name, size_t nameSize) {
    if (length < 53) return false;
    *format = get_u16_le(payload + 4);
    *size = get_u32_le(payload + 8);
    if (ptp_string_to_ascii(payload + 52, length - 52, name, nameSize) < 0) return false;
    size_t n = strlen(name);
    bool extension = (n >= 4 && !strcasecmp(name + n - 4, ".jpg")) ||
                     (n >= 5 && !strcasecmp(name + n - 5, ".jpeg"));
    return *format == 0x3801 || extension; /* EXIF/JFIF JPEG */
}

static int inspect_jpeg_candidate(libusb_device_handle *dev, uint32_t handle,
                                  ConversionRetrieval *result) {
    uint32_t params[] = {handle};
    int rc = ptp_send(dev, 0x1008, 1, params); /* GetObjectInfo */
    if (rc != LIBUSB_SUCCESS) return rc;
    PtpContainer info;
    rc = ptp_read_data_and_ok_response(dev, 0x1008, g_transactionId, &info);
    if (rc != LIBUSB_SUCCESS) return rc;
    result->inspected_count++;
    uint16_t format = 0; uint32_t size = 0; char name[128] = "";
    bool isJPEG = object_info_is_jpeg(info.payload, info.payloadLength, &format, &size, name, sizeof(name));
    ptp_container_free(&info);
    if (!isJPEG) return 0;
    if (result->candidate_handle != 0) return 1; /* ambiguous: do not choose */
    result->candidate_handle = handle;
    result->candidate_format = format;
    result->candidate_size = size;
    snprintf(result->candidate_name, sizeof(result->candidate_name), "%s", name);
    return 0;
}

static int download_verified_jpeg(libusb_device_handle *dev, const char *outPath,
                                  ConversionRetrieval *result) {
    uint32_t params[] = {result->candidate_handle};
    int rc = ptp_send(dev, 0x1009, 1, params); /* GetObject */
    if (rc != LIBUSB_SUCCESS) return rc;
    PtpContainer data;
    rc = ptp_read_data_and_ok_response(dev, 0x1009, g_transactionId, &data);
    if (rc != LIBUSB_SUCCESS) return rc;
    /* Metadata is necessary but not sufficient: verify a JPEG SOI before
     * persisting an automatically-selected object. */
    if (data.payloadLength < 2 || data.payload[0] != 0xFF || data.payload[1] != 0xD8) {
        ptp_container_free(&data);
        return -96;
    }
    FILE *f = fopen(outPath, "wb");
    if (!f) { ptp_container_free(&data); return -98; }
    size_t written = fwrite(data.payload, 1, data.payloadLength, f);
    fclose(f);
    result->candidate_size = data.payloadLength;
    ptp_container_free(&data);
    if (written != result->candidate_size) return -98;
    result->downloaded = true;
    return 0;
}

static ConversionRetrieval wait_for_result(libusb_device_handle *dev, const char *outPath, int timeoutMs) {
    ConversionRetrieval result = {.rc = 0, .state = "no_retrievable_output"};
    result.baseline_count = g_conversion_baseline.count;
    if (!g_conversion_baseline_captured) {
        result.rc = -95; result.state = "indeterminate_no_baseline"; return result;
    }
    for (int elapsed = 0; elapsed < timeoutMs; elapsed += 1000) {
        ObjectInventory post = {NULL, 0};
        int rc = capture_object_inventory(dev, &post);
        if (rc != 0) { result.rc = rc; result.state = "inventory_failed"; return result; }
        result.post_count = post.count; result.new_count = 0; result.inspected_count = 0;
        result.candidate_handle = 0; result.candidate_name[0] = '\0';
        bool ambiguous = false;
        for (uint32_t i = 0; i < post.count; i++) if (!inventory_contains(&g_conversion_baseline, post.handles[i])) {
            result.new_count++;
            int inspection = inspect_jpeg_candidate(dev, post.handles[i], &result);
            if (inspection < 0) { result.rc = inspection; result.state = "object_info_failed"; inventory_free(&post); return result; }
            if (inspection > 0) ambiguous = true;
        }
        inventory_free(&post);
        if (ambiguous) { result.state = "indeterminate_multiple_jpeg_candidates"; return result; }
        if (result.candidate_handle) {
            rc = download_verified_jpeg(dev, outPath, &result);
            result.rc = rc;
            result.state = rc == 0 ? "jpeg_downloaded" : "candidate_not_downloaded";
            return result;
        }
        usleep(1000000);
    }
    result.state = result.new_count ? "no_jpeg_candidate" : "no_new_object";
    return result;
}

/* Associate every retrieval attempt with the object set observed immediately
 * before the trigger. Without this baseline, a pre-existing card JPEG is
 * indistinguishable from a conversion result, so do not trigger automatically. */
static int trigger_conversion_with_baseline(libusb_device_handle *dev) {
    /* Do not reuse a prior successful inventory if this new capture fails. */
    g_conversion_baseline_captured = false;
    int rc = capture_object_inventory(dev, &g_conversion_baseline);
    if (rc != 0) {
        fprintf(stderr, "[CONVERT] Baseline inventory failed: rc=%d; trigger not sent\n", rc);
        return rc;
    }
    g_conversion_baseline_captured = true;
    fprintf(stderr, "[CONVERT] Baseline inventory: %u handles\n", g_conversion_baseline.count);
    return trigger_conversion(dev);
}

/* Write a uint16 property value (helper wrapper) */
static int write_prop_u16(libusb_device_handle *dev, uint16_t prop, uint16_t val) {
    uint8_t data[2] = { val & 0xFF, (val >> 8) & 0xFF };
    return write_prop(dev, prop, data, 2);
}

/* Encode a UTF-8 string as a PTP string: one count byte, UCS-2LE code units,
 * and a terminating U+0000.  PTP's UCS-2 representation cannot encode
 * supplementary-plane Unicode, so reject it instead of silently truncating. */
static int utf8_to_ptp_string(const char *utf8, uint8_t *out, uint32_t outCapacity,
                              uint32_t *outLen) {
    const uint8_t *p = (const uint8_t *)utf8;
    const uint8_t *end = p + strlen(utf8);
    uint32_t units = 0;
    uint32_t offset = 1;

    while (p < end) {
        uint32_t cp;
        if (*p < 0x80) {
            cp = *p++;
        } else if ((*p & 0xE0) == 0xC0 && end - p >= 2 && (p[1] & 0xC0) == 0x80) {
            cp = ((*p & 0x1F) << 6) | (p[1] & 0x3F);
            if (cp < 0x80) return -1;  /* overlong */
            p += 2;
        } else if ((*p & 0xF0) == 0xE0 && end - p >= 3 &&
                   (p[1] & 0xC0) == 0x80 && (p[2] & 0xC0) == 0x80) {
            cp = ((*p & 0x0F) << 12) | ((p[1] & 0x3F) << 6) | (p[2] & 0x3F);
            if (cp < 0x800) return -1;  /* overlong */
            p += 3;
        } else if ((*p & 0xF8) == 0xF0 && end - p >= 4 &&
                   (p[1] & 0xC0) == 0x80 && (p[2] & 0xC0) == 0x80 &&
                   (p[3] & 0xC0) == 0x80) {
            cp = ((*p & 0x07) << 18) | ((p[1] & 0x3F) << 12) |
                 ((p[2] & 0x3F) << 6) | (p[3] & 0x3F);
            if (cp < 0x10000 || cp > 0x10FFFF) return -1;
            return -2;  /* valid UTF-8 but not representable in UCS-2 */
        } else {
            return -1;
        }

        if (cp == 0 || (cp >= 0xD800 && cp <= 0xDFFF)) return -1;
        if (units >= 254 || offset + 2 > outCapacity) return -3;
        put_u16_le(out + offset, (uint16_t)cp);
        offset += 2;
        units++;
    }

    if (offset + 2 > outCapacity) return -3;
    put_u16_le(out + offset, 0);
    out[0] = (uint8_t)(units + 1);  /* count includes terminator */
    *outLen = offset + 2;
    return 0;
}

/* Encode the exact D18D payload and enforce the camera's stricter label
 * contract before selecting a slot or sending SetDevicePropValue. */
static int validate_preset_name_payload(const uint8_t *data) {
    uint32_t characters = data[0] == 0 ? 0 : data[0] - 1;
    if (characters > FUJI_PRESET_NAME_MAX_CHARACTERS) return -404;
    for (uint32_t i = 0; i < characters; i++) {
        uint16_t ch = data[1 + i * 2] | (data[2 + i * 2] << 8);
        if (ch < 0x20 || ch > 0x7E) return -405;
    }
    return 0;
}

static int encode_preset_name(const char *value, uint8_t *data, uint32_t capacity,
                              uint32_t *dataLen) {
    int rc = utf8_to_ptp_string(value, data, capacity, dataLen);
    return rc == 0 ? validate_preset_name_payload(data) : rc;
}

/* Decode a PTP UCS-2 string to UTF-8 for C-slot readback. */
static int ptp_string_to_utf8(const uint8_t *data, uint32_t dataLen,
                              char *out, uint32_t outCapacity) {
    if (dataLen == 0) {
        if (outCapacity == 0) return -1;
        out[0] = '\0';
        return 0;
    }
    uint32_t count = data[0];
    if (count == 0 || dataLen != 1 + count * 2 || count < 1) return -1;

    uint32_t write = 0;
    for (uint32_t i = 0; i + 1 < count; i++) {
        uint16_t ch = data[1 + i * 2] | (data[2 + i * 2] << 8);
        if (ch >= 0xD800 && ch <= 0xDFFF) return -1;
        if (ch < 0x80) {
            if (write + 1 >= outCapacity) return -1;
            out[write++] = (char)ch;
        } else if (ch < 0x800) {
            if (write + 2 >= outCapacity) return -1;
            out[write++] = (char)(0xC0 | (ch >> 6));
            out[write++] = (char)(0x80 | (ch & 0x3F));
        } else {
            if (write + 3 >= outCapacity) return -1;
            out[write++] = (char)(0xE0 | (ch >> 12));
            out[write++] = (char)(0x80 | ((ch >> 6) & 0x3F));
            out[write++] = (char)(0x80 | (ch & 0x3F));
        }
    }
    if (data[1 + (count - 1) * 2] != 0 || data[2 + (count - 1) * 2] != 0) return -1;
    if (write >= outCapacity) return -1;
    out[write] = '\0';
    return 0;
}

static int write_prop_string(libusb_device_handle *dev, uint16_t prop, const char *value) {
    uint8_t data[511];
    uint32_t dataLen = 0;
    int rc = encode_preset_name(value, data, sizeof(data), &dataLen);
    if (rc != 0) return rc;
    fprintf(stderr, "[DEBUG] D18D payload: chars=%u bytes=%u hex=",
            data[0] == 0 ? 0 : data[0] - 1, dataLen);
    for (uint32_t i = 0; i < dataLen; i++) fprintf(stderr, "%02X", data[i]);
    fprintf(stderr, "\n");
    return write_prop(dev, prop, data, dataLen);
}

/* Write a uint32 property value (helper wrapper) */
static int write_prop_u32(libusb_device_handle *dev, uint16_t prop, uint32_t val) {
    uint8_t data[4] = { val & 0xFF, (val >> 8) & 0xFF, (val >> 16) & 0xFF, (val >> 24) & 0xFF };
    return write_prop(dev, prop, data, 4);
}

/* Write a property value (three-phase: COMMAND, DATA, RESPONSE) */
static int write_prop(libusb_device_handle *dev, uint16_t prop, uint8_t *data, uint32_t dataLen) {
    uint8_t resp[64]; int len = 0;
    uint32_t params[] = {prop};

    /* SetDevicePropValue: 0x1016 - three-phase write */
    /* Phase 1: Send COMMAND container */
    int rc = ptp_send(dev, 0x1016, 1, params);
    fprintf(stderr, "[DEBUG] write_prop CMD: rc=%d\n", rc);
    if (rc != LIBUSB_SUCCESS) return -10;

    /* Phase 2: Send DATA container with the COMMAND transaction ID.
     * Do not construct this in a fixed-size local buffer: preset names are
     * PTP strings and can legitimately exceed 52 bytes (12-byte header plus
     * payload).  The old 64-byte buffer overflowed before libusb was called,
     * causing macOS's checked memcpy to terminate the helper with SIGTRAP.
     * ptp_send_data builds an exact-size container and also handles large
     * profile payloads safely. */
    fprintf(stderr, "[DEBUG] write_prop DATA: totalLen=%u transId=%u\n",
            12 + dataLen, g_transactionId);
    rc = ptp_send_data(dev, 0x1016, g_transactionId, data, dataLen);
    fprintf(stderr, "[DEBUG] write_prop DATA sent: rc=%d\n", rc);
    if (rc != LIBUSB_SUCCESS) return -11;

    /* Phase 3: Receive RESPONSE container */
    rc = ptp_recv(dev, resp, sizeof(resp), &len);
    if (rc != LIBUSB_SUCCESS) return rc;
    if (len < 12) return -2;

    uint16_t type = resp[4] | (resp[5] << 8);
    uint16_t code = resp[6] | (resp[7] << 8);
    fprintf(stderr, "[DEBUG] write_prop RESP: type=0x%04X code=0x%04X\n", type, code);
    if (type != 0x0003) return -3;  /* Expected Response */

    return (code == 0x2001) ? 0 : (int)code;
}

/* Reset USB connection to recover from stalled device */
static int reset_device(libusb_device_handle *dev) {
    fprintf(stderr, "[HELPER] Resetting USB connection...\n");
    libusb_release_interface(dev, 0);
    libusb_close(dev);
    return -99;  /* Signal that dev needs full reconnect */
}

/* ── Connection Helpers (for reconnect) ─────────────────────────────── */

/* Forward declarations for connect/disconnect helpers */
static int do_open_device(libusb_context *ctx, libusb_device_handle **dev);
static int do_open_device_attempt(libusb_context *ctx, libusb_device_handle **dev,
                                  bool recoverStaleSession, bool recoverTimeout);
static void do_close_device(libusb_device_handle **dev);

/* Open device, claim interface, send OpenSession — reusable for connect/reconnect */
static int do_open_device_attempt(libusb_context *ctx, libusb_device_handle **dev,
                                  bool recoverStaleSession, bool recoverTimeout) {
    libusb_device_handle *h = libusb_open_device_with_vid_pid(ctx, FUJI_VENDOR, X100VI_PRODUCT);
    if (!h) return -1;

    /* Get device info */
    struct libusb_device_descriptor desc;
    if (libusb_get_device_descriptor(libusb_get_device(h), &desc) == LIBUSB_SUCCESS) {
        char vendor[256]={0}, product[256]={0}, serial[256]={0};
        libusb_get_string_descriptor_ascii(h, desc.iManufacturer, (unsigned char*)vendor, sizeof(vendor));
        libusb_get_string_descriptor_ascii(h, desc.iProduct, (unsigned char*)product, sizeof(product));
        libusb_get_string_descriptor_ascii(h, desc.iSerialNumber, (unsigned char*)serial, sizeof(serial));
        fprintf(stderr, "[HELPER] Found: %s %s (SN: %s)\n", vendor, product, serial);
    }

    /* Prepare USB connection */
    libusb_detach_kernel_driver(h, 0);
    libusb_set_configuration(h, 1);
    int rc = libusb_claim_interface(h, 0);
    if (rc != LIBUSB_SUCCESS) {
        fprintf(stderr, "[HELPER] Failed to claim interface: %s\n", libusb_error_name(rc));
        libusb_close(h);
        return -2;
    }

    /* Clear endpoint halts after fresh connection (macOS libusb quirk) */
    clear_endpoint_halt(h, 0x81);
    clear_endpoint_halt(h, 0x01);
    ptp_reset_transport_state();
    usleep(100000);  /* 100ms settle after clear */

    /* OpenSession carries a non-zero SessionID. A fresh transport must issue
     * it as transaction ID 1; ptp_reset_transport_state above guarantees it. */
    fprintf(stderr, "[HELPER] Sending OpenSession with transaction ID 1...\n");
    uint16_t sessionResponseCode = 0;
    rc = ptp_send_session_command(h, 0x1002, true, &sessionResponseCode);
    if (rc != LIBUSB_SUCCESS) {
        g_lastSessionTransportError = rc;
        do_close_device(&h);
        /* macOS's PTP service can release the interface just after it has
         * stopped owning it. The first OpenSession response is then lost even
         * though the camera was found and the interface was claimed. Reopen
         * once after a short settle; this sends no camera object operation. */
        if (rc == LIBUSB_ERROR_TIMEOUT && recoverTimeout) {
            fprintf(stderr,
                    "[HELPER] OpenSession response timed out; reopening USB once before failing...\n");
            usleep(500000);
            return do_open_device_attempt(ctx, dev, recoverStaleSession, false);
        }
        return -3;
    }
    if (sessionResponseCode == 0x201E && recoverStaleSession) {
        /* A previous helper may have released USB without closing PTP. Close
         * the stale session, release USB, reset all local state, then retry
         * exactly once; the retry's OpenSession is again transaction ID 1. */
        fprintf(stderr, "[HELPER] SessionAlreadyOpen; closing stale session before retry...\n");
        uint16_t closeResponseCode = 0;
        int closeRc = ptp_send_session_command(h, 0x1003, false, &closeResponseCode);
        if (closeRc != LIBUSB_SUCCESS || closeResponseCode != 0x2001) {
            fprintf(stderr,
                    "[HELPER] Stale CloseSession was not acknowledged: transport=%d code=0x%04X\n",
                    closeRc, closeResponseCode);
        }
        do_close_device(&h);
        usleep(500000);
        return do_open_device_attempt(ctx, dev, false, recoverTimeout);
    }
    if (sessionResponseCode != 0x2001) {
        fprintf(stderr, "[HELPER] OpenSession rejected: code=0x%04X (expected 0x2001)\n",
                sessionResponseCode);
        do_close_device(&h);
        return (int)sessionResponseCode;
    }

    g_sessionOpen = true;
    *dev = h;
    return 0;
}

static int do_open_device(libusb_context *ctx, libusb_device_handle **dev) {
    g_lastSessionTransportError = 0;
    return do_open_device_attempt(ctx, dev, true, true);
}

/* Close device and release interface */
static void do_close_device(libusb_device_handle **dev) {
    if (*dev) {
        if (g_sessionOpen) {
            uint16_t closeResponseCode = 0;
            int closeRc = ptp_send_session_command(*dev, 0x1003, false,
                                                    &closeResponseCode);
            if (closeRc != LIBUSB_SUCCESS || closeResponseCode != 0x2001) {
                fprintf(stderr,
                        "[HELPER] CloseSession was not acknowledged: transport=%d code=0x%04X\n",
                        closeRc, closeResponseCode);
            }
        }
        libusb_release_interface(*dev, 0);
        libusb_close(*dev);
        *dev = NULL;
    }
    ptp_reset_transport_state();
}

/* ── Command Parsing ─────────────────────────────────────────────────── */

static const char *json_find_value(const char *json, const char *key) {
    static char pattern[64];
    snprintf(pattern, sizeof(pattern), "\"%s\"", key);
    const char *p = strstr(json, pattern);
    if (!p) return NULL;
    p += strlen(pattern);
    while (*p == ' ' || *p == ':') p++;
    return p;
}

/* Simple JSON string value extractor.  It decodes JSON escapes into UTF-8 so
 * quoted C-slot names survive the helper boundary before UCS-2 validation. */
static const char *json_get_string(const char *json, const char *key) {
    const char *p = json_find_value(json, key);
    if (!p) return NULL;
    if (*p != '"') return NULL;
    p++;
    static char buf[1024];
    size_t out = 0;
    while (*p && *p != '"') {
        unsigned char ch = (unsigned char)*p++;
        if (ch != '\\') {
            if (ch < 0x20 || out + 1 >= sizeof(buf)) return NULL;
            buf[out++] = (char)ch;
            continue;
        }
        char escaped = *p++;
        if (!escaped) return NULL;
        switch (escaped) {
            case '"': case '\\': case '/': buf[out++] = escaped; break;
            case 'b': buf[out++] = '\b'; break;
            case 'f': buf[out++] = '\f'; break;
            case 'n': buf[out++] = '\n'; break;
            case 'r': buf[out++] = '\r'; break;
            case 't': buf[out++] = '\t'; break;
            case 'u': {
                uint16_t cp = 0;
                for (int i = 0; i < 4; i++) {
                    char hex = *p++;
                    if (hex >= '0' && hex <= '9') cp = (uint16_t)((cp << 4) | (hex - '0'));
                    else if (hex >= 'a' && hex <= 'f') cp = (uint16_t)((cp << 4) | (hex - 'a' + 10));
                    else if (hex >= 'A' && hex <= 'F') cp = (uint16_t)((cp << 4) | (hex - 'A' + 10));
                    else return NULL;
                }
                if (cp >= 0xD800 && cp <= 0xDFFF) return NULL;
                if (cp < 0x80) {
                    if (out + 1 >= sizeof(buf)) return NULL;
                    buf[out++] = (char)cp;
                } else if (cp < 0x800) {
                    if (out + 2 >= sizeof(buf)) return NULL;
                    buf[out++] = (char)(0xC0 | (cp >> 6));
                    buf[out++] = (char)(0x80 | (cp & 0x3F));
                } else {
                    if (out + 3 >= sizeof(buf)) return NULL;
                    buf[out++] = (char)(0xE0 | (cp >> 12));
                    buf[out++] = (char)(0x80 | ((cp >> 6) & 0x3F));
                    buf[out++] = (char)(0x80 | (cp & 0x3F));
                }
                break;
            }
            default: return NULL;
        }
        if (out >= sizeof(buf)) return NULL;
    }
    if (*p != '"') return NULL;
    buf[out] = 0;
    return buf;
}

static int json_get_int(const char *json, const char *key, int def) {
    const char *p = json_find_value(json, key);
    if (!p) return def;
    if ((*p >= '0' && *p <= '9') || *p == '-') {
        return atoi(p);
    }
    return def;
}

/* C-slot JSON values are camera preset values, not active-setting/UI values.
 * In particular, grain is 1...5 and the effect fields are 1...3. */
static bool preset_value_is_valid(uint16_t code, uint16_t value) {
    int16_t signedValue = (int16_t)value;
    switch (code) {
        case 0xD190: return value == 100 || value == 200 || value == 400 || value == 0xFFFF;
        case 0xD195: return value >= 1 && value <= 5;
        case 0xD196:
        case 0xD197:
        case 0xD198: return value >= 1 && value <= 3;
        case 0xD199:
            return value == 0 || value == 2 || value == 4 || value == 6 || value == 8 ||
                   (value >= 0x8001 && value <= 0x8003) || value == 0x8006 ||
                   value == 0x8007 || value == 0x8020 || value == 0x8021;
        case 0xD19A:
        case 0xD19B: return signedValue >= -9 && signedValue <= 9;
        case 0xD19C: return value >= 2500 && value <= 10000;
        case 0xD19D:
        case 0xD19E: return signedValue >= -20 && signedValue <= 40;
        case 0xD19F:
        case 0xD1A0: return signedValue >= -40 && signedValue <= 40;
        case 0xD1A1:
            return value == 0x8000 || value == 0x7000 || value == 0x4000 ||
                   value == 0x3000 || value == 0x2000 || value == 0x1000 ||
                   value == 0x0000 || value == 0x6000 || value == 0x5000;
        case 0xD1A2: return signedValue >= -50 && signedValue <= 50;
        case 0xD1A3: return value <= 1;
        case 0xD1A4: return value == 1 || value == 2;
        default: return true;
    }
}

static bool is_monochrome_film_sim(uint16_t filmSimulation) {
    return (filmSimulation >= 6 && filmSimulation <= 10) ||
           (filmSimulation >= 12 && filmSimulation <= 15);
}

/* Do not send known-inapplicable fields.  Their omitted value remains intact
 * in the selected C-slot, which is essential for exact backup restoration. */
static bool should_skip_conditional_field(uint16_t code, uint16_t value,
                                          const bool *requested,
                                          const uint16_t *values,
                                          int fieldCount) {
    int filmIndex = -1, wbIndex = -1;
    for (int i = 0; i < fieldCount; i++) {
        if (preset_fields[i].code == 0xD192) filmIndex = i;
        if (preset_fields[i].code == 0xD199) wbIndex = i;
    }
    if ((code == 0xD193 || code == 0xD194) && filmIndex >= 0 && requested[filmIndex]) {
        return !is_monochrome_film_sim(values[filmIndex]) || value == 0;
    }
    if (code == 0xD19C && wbIndex >= 0 && requested[wbIndex]) {
        return values[wbIndex] != 0x8007 || value == 0;
    }
    if (code == 0xD19F && filmIndex >= 0 && requested[filmIndex]) {
        return is_monochrome_film_sim(values[filmIndex]);
    }
    return false;
}

static int verify_preset_u16(libusb_device_handle *dev, uint16_t prop, uint16_t expected) {
    uint32_t actual = 0;
    int rc = read_prop(dev, prop, &actual);
    if (rc != 0) return rc;
    return ((uint16_t)actual == expected) ? 0 : -300;
}

static int verify_preset_name(libusb_device_handle *dev, const char *expected) {
    uint8_t payload[511];
    uint32_t payloadLen = 0;
    int rc = read_prop_payload(dev, 0xD18D, payload, sizeof(payload), &payloadLen);
    if (rc != 0) return rc;
    char actual[1024];
    if (ptp_string_to_utf8(payload, payloadLen, actual, sizeof(actual)) != 0) return -301;
    return strcmp(actual, expected) == 0 ? 0 : -302;
}

/* A never-configured C slot is represented by an empty name and successful
 * zero-valued reads for every numeric preset property.  Those zeros are a
 * camera sentinel, not values that SetDevicePropValue accepts for every
 * property, so callers must never use this result as a restorable baseline. */
static int detect_empty_preset_slot(libusb_device_handle *dev, bool *isEmptySlot) {
    *isEmptySlot = false;
    for (int i = 0; preset_props[i].code; i++) {
        if (preset_props[i].code == 0xD18D) {
            uint8_t payload[511];
            uint32_t payloadLen = 0;
            char name[1024] = {0};
            int rc = read_prop_payload(dev, preset_props[i].code, payload, sizeof(payload), &payloadLen);
            if (rc != 0) return rc;
            if (ptp_string_to_utf8(payload, payloadLen, name, sizeof(name)) != 0) return -301;
            if (name[0] != '\0') return 0;
        } else {
            uint32_t value = 0;
            int rc = read_prop(dev, preset_props[i].code, &value);
            if (rc != 0) return rc;
            if (value != 0) return 0;
        }
    }
    *isEmptySlot = true;
    return 0;
}

static void print_preset_write_result(const char *id, int slot, int slotSelectRc, int baselineReadRc,
                                      bool nameRequested, int nameRc,
                                      const PresetField *fields, const bool *requested,
                                      const uint16_t *values, const int *writeRc, const int *verifyRc,
                                      int fieldCount, bool wasEmptySlot) {
    bool success = slotSelectRc == 0 && baselineReadRc == 0 && (!nameRequested || nameRc == 0);
    bool verified = success;
    for (int i = 0; i < fieldCount; i++) {
        if (!requested[i]) continue;
        bool warning = fields[i].conditional && writeRc[i] == 0x201C;
        if (!warning && (writeRc[i] != 0 || verifyRc[i] != 0)) {
            success = false;
            verified = false;
        }
    }
    if (nameRequested && nameRc == 0 && verifyRc[fieldCount] != 0) {
        success = false;
        verified = false;
    }

    const char *failureStage = "none";
    if (slotSelectRc != 0) failureStage = "slot_selection";
    else if (baselineReadRc != 0) failureStage = "baseline_read";
    else if (nameRequested && nameRc != 0) failureStage = "name_write";
    else if (!success || !verified) failureStage = "setting_write_or_verify";

    fprintf(stdout,
            "{\"id\":\"%s\",\"success\":%s,\"result\":{\"slot\":%d,"
            "\"slot_select_rc\":%d,\"baseline_read_rc\":%d,\"failure_stage\":\"%s\","
            "\"verified\":%s,\"is_empty_slot\":%s,"
            "\"created_from_empty\":%s,\"warnings\":[",
            id, success ? "true" : "false", slot, slotSelectRc, baselineReadRc, failureStage,
            verified ? "true" : "false", wasEmptySlot ? "true" : "false",
            (success && verified && wasEmptySlot) ? "true" : "false");
    bool first = true;
    for (int i = 0; i < fieldCount; i++) {
        if (!requested[i] || !fields[i].conditional || writeRc[i] != 0x201C) continue;
        if (!first) fputc(',', stdout);
        first = false;
        fprintf(stdout, "{\"property\":\"0x%04X\",\"key\":\"%s\",\"response_code\":\"0x201C\"}",
                fields[i].code, fields[i].key);
    }
    fprintf(stdout, "],\"errors\":[");
    first = true;
    if (slotSelectRc != 0) {
        fprintf(stdout, "{\"stage\":\"slot_selection\",\"property\":\"0xD18C\",\"key\":\"slot\",\"rc\":%d}", slotSelectRc);
        first = false;
    }
    if (baselineReadRc != 0) {
        if (!first) fputc(',', stdout);
        fprintf(stdout, "{\"stage\":\"baseline_read\",\"property\":\"C-slot baseline\",\"rc\":%d}", baselineReadRc);
        first = false;
    }
    if (nameRequested && nameRc != 0) {
        if (!first) fputc(',', stdout);
        fprintf(stdout, "{\"stage\":\"name_write\",\"property\":\"0xD18D\",\"key\":\"name\",\"rc\":%d}", nameRc);
        first = false;
    } else if (nameRequested && verifyRc[fieldCount] != 0) {
        if (!first) fputc(',', stdout);
        fprintf(stdout, "{\"stage\":\"name_verify\",\"property\":\"0xD18D\",\"key\":\"name\",\"rc\":%d}", verifyRc[fieldCount]);
        first = false;
    }
    for (int i = 0; i < fieldCount; i++) {
        if (!requested[i]) continue;
        bool warning = fields[i].conditional && writeRc[i] == 0x201C;
        int rc = writeRc[i] != 0 ? writeRc[i] : verifyRc[i];
        if (warning || rc == 0) continue;
        if (!first) fputc(',', stdout);
        fprintf(stdout,
                "{\"stage\":\"setting_write_or_verify\",\"property\":\"0x%04X\",\"key\":\"%s\",\"requested_raw\":\"0x%04X\",\"rc\":%d}",
                fields[i].code, fields[i].key, values[i], rc);
        first = false;
    }
    fprintf(stdout, "]}}\n");
}

/* ── Main Loop ───────────────────────────────────────────────────────── */

#ifndef PTP_FRAME_FIXTURE_TEST
int main(int argc, char *argv[]) {
    libusb_context *ctx = NULL;
    libusb_device_handle *dev = NULL;
    int rc;

    /* Init libusb */
    rc = libusb_init(&ctx);
    if (rc != LIBUSB_SUCCESS) {
        fprintf(stderr, "libusb_init failed: %s\n", libusb_error_name(rc));
        return 1;
    }
    libusb_set_debug(ctx, 0);

    /* Main command loop */
    char line[4096];
    while (fgets(line, sizeof(line), stdin)) {
        /* Trim newline */
        size_t len = strlen(line);
        while (len > 0 && (line[len-1] == '\n' || line[len-1] == '\r'))
            line[--len] = 0;
        if (len == 0) continue;

        const char *cmd = json_get_string(line, "command");
        if (!cmd) {
            fprintf(stdout, "{\"id\":\"error\",\"success\":false,\"error\":\"missing_command\"}\n");
            fflush(stdout);
            continue;
        }

        /* ── ping ── */
        if (!strcmp(cmd, "ping")) {
            fprintf(stdout, "{\"id\":\"%s\",\"success\":true,\"result\":\"ok\"}\n",
                    json_get_string(line, "id") ? json_get_string(line, "id") : "0");
            fflush(stdout);
            continue;
        }

        /* ── inspect_preset_name ──
         * Offline diagnostic for the exact D18D payload. It never opens or
         * writes a camera, and is used by regression checks to compare this
         * helper's bytes with FilmKit's standard PTP-string representation. */
        if (!strcmp(cmd, "inspect_preset_name")) {
            char id[128];
            const char *requestId = json_get_string(line, "id");
            snprintf(id, sizeof(id), "%s", requestId ? requestId : "0");
            const char *name = json_get_string(line, "name");
            uint8_t payload[511];
            uint32_t payloadLen = 0;
            int encodeRc = name ? utf8_to_ptp_string(name, payload, sizeof(payload), &payloadLen) : -401;
            int nameRc = encodeRc == 0 ? validate_preset_name_payload(payload) : encodeRc;
            fprintf(stdout, "{\"id\":\"%s\",\"success\":%s,\"result\":{\"rc\":%d",
                    id, nameRc == 0 ? "true" : "false", nameRc);
            if (encodeRc == 0) {
                fprintf(stdout, ",\"characters\":%u,\"ptp_payload_hex\":\"",
                        payload[0] == 0 ? 0 : payload[0] - 1);
                for (uint32_t i = 0; i < payloadLen; i++) fprintf(stdout, "%02X", payload[i]);
                fprintf(stdout, "\"");
            }
            fprintf(stdout, "}}\n");
            fflush(stdout);
            continue;
        }

        /* ── connect ── */
        if (!strcmp(cmd, "connect")) {
            if (dev) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"already_connected\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }

            fprintf(stderr, "[HELPER] Connecting...\n");
            rc = do_open_device(ctx, &dev);
            if (rc != 0) {
                const char *errMsg = rc == -1 ? "camera_not_found"
                    : (rc == -2 ? "interface_claim_failed" : "session_open_failed");
                fprintf(stdout,
                        "{\"id\":\"%s\",\"success\":false,\"error\":\"%s\",\"code\":%d,"
                        "\"transport_code\":%d}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0",
                        errMsg, rc, g_lastSessionTransportError);
                fflush(stdout);
                continue;
            }

            fprintf(stdout, "{\"id\":\"%s\",\"success\":true,\"result\":\"connected\"}\n",
                    json_get_string(line, "id") ? json_get_string(line, "id") : "0");
            fflush(stdout);
            continue;
        }

        /* ── reconnect ──
         * Close and reopen the USB connection. Workaround for macOS libusb
         * IN endpoint breakage after large vendor transfers (RAF upload).
         * After reconnect, the PTP session is fresh but camera state
         * (loaded RAF) persists in the camera's memory.
         */
        if (!strcmp(cmd, "reconnect")) {
            if (!dev) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"not_connected\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }

            fprintf(stderr, "[HELPER] Reconnecting (close → open → OpenSession)...\n");
            do_close_device(&dev);

            /* Pause to let macOS USB stack settle after large vendor transfer */
            usleep(500000);  /* 500ms — macOS needs more time */

            rc = do_open_device(ctx, &dev);
            if (rc != 0) {
                const char *errMsg = rc == -1 ? "camera_not_found"
                    : (rc == -2 ? "interface_claim_failed" : "session_open_failed");
                fprintf(stdout,
                        "{\"id\":\"%s\",\"success\":false,\"error\":\"reconnect_%s\",\"code\":%d,"
                        "\"transport_code\":%d}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0",
                        errMsg, rc, g_lastSessionTransportError);
                fflush(stdout);
                continue;
            }

            fprintf(stdout, "{\"id\":\"%s\",\"success\":true,\"result\":\"reconnected\"}\n",
                    json_get_string(line, "id") ? json_get_string(line, "id") : "0");
            fflush(stdout);
            continue;
        }

        /* ── disconnect ── */
        if (!strcmp(cmd, "disconnect")) {
            do_close_device(&dev);
            fprintf(stdout, "{\"id\":\"%s\",\"success\":true,\"result\":\"disconnected\"}\n",
                    json_get_string(line, "id") ? json_get_string(line, "id") : "0");
            fflush(stdout);
            continue;
        }

        /* ── read_property ── */
        if (!strcmp(cmd, "read_property")) {
            if (!dev) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"not_connected\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }
            uint16_t prop = (uint16_t)json_get_int(line, "code", 0);
            uint32_t val = 0;
            rc = read_prop(dev, prop, &val);
            const char *r = NULL;
            /* Try to resolve the value */
            for (int i = 0; preset_props[i].code; i++) {
                if (preset_props[i].code == prop) { r = resolve(preset_props[i].key, val); break; }
            }
            for (int i = 0; active_props[i].code; i++) {
                if (active_props[i].code == prop) { r = resolve(active_props[i].key, val); break; }
            }
            fprintf(stdout, "{\"id\":\"%s\",\"success\":%s,\"result\":{\"code\":%u,\"value\":%u",
                    json_get_string(line, "id") ? json_get_string(line, "id") : "0",
                    rc == 0 ? "true" : "false", prop, val);
            if (r) fprintf(stdout, ",\"display\":\"%s\"", r);
            if (rc != 0) fprintf(stdout, ",\"error_code\":%d", rc);
            fprintf(stdout, "}}\n");
            fflush(stdout);
            continue;
        }

        /* ── write_property ── */
        if (!strcmp(cmd, "write_property")) {
            if (!dev) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"not_connected\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }
            uint16_t prop = (uint16_t)json_get_int(line, "code", 0);
            uint32_t val = (uint32_t)json_get_int(line, "value", 0);
            rc = write_prop_u32(dev, prop, val);
            if (rc == 0) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":true,\"result\":\"ok\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
            } else {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"result\":{\"error\":\"write_failed\",\"code\":%d}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0", rc);
            }
            fflush(stdout);
            continue;
        }

        /* ── read_preset_slot ── */
        if (!strcmp(cmd, "read_preset_slot")) {
            if (!dev) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"not_connected\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }
            int slot = json_get_int(line, "index", 0);
            int slotSelRc = (slot >= 1 && slot <= 7)
                ? write_prop_u16(dev, 0xD18C, (uint16_t)slot) : -400;
            if (slotSelRc != 0) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"result\":{\"slot\":%d,"
                        "\"slot_select_rc\":%d,\"failure_stage\":\"slot_selection\","
                        "\"error\":\"slot_select_failed\"}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0",
                        slot, slotSelRc);
                fflush(stdout);
                continue;
            }
            usleep(100000);  /* 100ms for camera to switch slot (matches FilmKit) */

            /* Read all preset properties.  An empty name plus all-zero raw
             * values is the camera's never-configured-slot sentinel. */
            bool isEmptySlot = true;
            fprintf(stdout, "{\"id\":\"%s\",\"success\":true,\"result\":{\"slot\":%d,\"slot_select_rc\":%d,\"properties\":{",

                    json_get_string(line, "id") ? json_get_string(line, "id") : "0", slot, slotSelRc);
            bool first = true;
            for (int i = 0; preset_props[i].code; i++) {
                uint32_t val = 0;
                int r = 0;
                char name[1024] = {0};
                bool isName = preset_props[i].code == 0xD18D;
                if (isName) {
                    uint8_t payload[511];
                    uint32_t payloadLen = 0;
                    r = read_prop_payload(dev, preset_props[i].code, payload, sizeof(payload), &payloadLen);
                    if (r == 0 && ptp_string_to_utf8(payload, payloadLen, name, sizeof(name)) != 0) r = -301;
                    if (r != 0 || name[0] != '\0') isEmptySlot = false;
                } else {
                    r = read_prop(dev, preset_props[i].code, &val);
                    if (r != 0 || val != 0) isEmptySlot = false;
                }
                if (!first) fprintf(stdout, ",");
                first = false;
                fprintf(stdout, "\"0x%04X_%s\":{\"rc\":%d,\"raw\":%u",
                        preset_props[i].code, preset_props[i].name, r, val);
                if (r == 0 && isName) {
                    fprintf(stdout, ",\"display\":");
                    json_escape_string(stdout, name);
                } else if (r == 0) {
                    const char *display = resolve(preset_props[i].key, val);
                    if (display) fprintf(stdout, ",\"display\":\"%s\"", display);
                }
                fprintf(stdout, "}");
            }
            fprintf(stdout, "},\"is_empty_slot\":%s}}\n", isEmptySlot ? "true" : "false");
            fflush(stdout);
            continue;
        }

        /* ── write_preset_slot ── */
        if (!strcmp(cmd, "write_preset_slot")) {
            if (!dev) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"not_connected\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }
            int slot = json_get_int(line, "index", 0);
            const char *requestId = json_get_string(line, "id");
            char id[128];
            snprintf(id, sizeof(id), "%s", requestId ? requestId : "0");

            bool requested[sizeof(preset_fields) / sizeof(preset_fields[0])] = {false};
            int writeRc[sizeof(preset_fields) / sizeof(preset_fields[0])] = {0};
            int verifyRc[sizeof(preset_fields) / sizeof(preset_fields[0])] = {0};
            uint16_t values[sizeof(preset_fields) / sizeof(preset_fields[0])] = {0};
            int fieldCount = 0;
            while (preset_fields[fieldCount].code) fieldCount++;

            bool nameRequested = json_find_value(line, "name") != NULL;
            int nameRc = 0;
            char name[1024] = {0};
            if (nameRequested) {
                const char *requestedName = json_get_string(line, "name");
                if (!requestedName) nameRc = -401;  /* invalid JSON string */
                else snprintf(name, sizeof(name), "%s", requestedName);
                if (nameRc == 0) {
                    uint8_t namePayload[511];
                    uint32_t namePayloadLen = 0;
                    nameRc = encode_preset_name(name, namePayload, sizeof(namePayload), &namePayloadLen);
                }
            }

            /* Validate the complete request before selecting a slot or
             * changing its name.  C-slot JSON is raw preset encoding: grain
             * is 1...5 and effect fields are 1...3, not UI 0-based values. */
            bool requestValid = (slot >= 1 && slot <= 7) && (!nameRequested || nameRc == 0);
            for (int i = 0; i < fieldCount; i++) {
                if (!json_find_value(line, preset_fields[i].key)) continue;
                requested[i] = true;
                int value = json_get_int(line, preset_fields[i].key, INT_MIN);
                /* read_preset_slot emits unsigned raw bits for every property.
                 * Accept those 0...65535 bit patterns for signed fields too,
                 * while also accepting their natural signed JSON form. */
                if (value == INT_MIN ||
                    (preset_fields[i].is_signed
                        ? (value < INT16_MIN || value > UINT16_MAX)
                        : (value < 0 || value > UINT16_MAX))) {
                    writeRc[i] = -402;
                    requestValid = false;
                    continue;
                }
                values[i] = (uint16_t)value;
                if (!preset_value_is_valid(preset_fields[i].code, values[i])) {
                    writeRc[i] = -403;
                    requestValid = false;
                }
            }

            if (!requestValid) {
                int preflightRc = (slot >= 1 && slot <= 7) ? 0 : -400;
                print_preset_write_result(id, slot, preflightRc, 0, nameRequested, nameRc,
                                          preset_fields, requested, values, writeRc, verifyRc, fieldCount, false);
                fflush(stdout);
                continue;
            }

            /* Film simulation and WB mode precede their dependent fields.
             * Omit known-inapplicable values rather than issue 0x201C writes. */
            for (int i = 0; i < fieldCount; i++) {
                if (requested[i] &&
                    should_skip_conditional_field(preset_fields[i].code, values[i],
                                                  requested, values, fieldCount)) {
                    requested[i] = false;
                }
            }

            bool wasEmptySlot = false;
            int slotSelRc = write_prop_u16(dev, 0xD18C, (uint16_t)slot);
            int baselineReadRc = 0;
            if (slotSelRc == 0) {
                usleep(100000);  /* verified FilmKit timing */
                /* Detect before the first mutation.  A detection error is a
                 * write error: without a reliable baseline we cannot report
                 * whether this is creation or update. */
                baselineReadRc = detect_empty_preset_slot(dev, &wasEmptySlot);
                if (baselineReadRc == 0 && nameRequested && nameRc == 0) {
                    nameRc = write_prop_string(dev, 0xD18D, name);
                }

                /* D18D is a core write.  Do not mutate additional settings if
                 * it was rejected or the supplied UTF-8 was not encodable. */
                if (baselineReadRc == 0 && (!nameRequested || nameRc == 0)) {
                    for (int i = 0; i < fieldCount; i++) {
                        if (!requested[i]) continue;
                        writeRc[i] = write_prop_u16(dev, preset_fields[i].code, values[i]);
                    }

                    /* Verify every accepted requested value before reporting success.
                     * Conditional InvalidDevicePropValue fields were not applied and
                     * are intentionally excluded from the comparison. */
                    if (nameRequested && nameRc == 0) verifyRc[fieldCount] = verify_preset_name(dev, name);
                    for (int i = 0; i < fieldCount; i++) {
                        if (!requested[i] || writeRc[i] != 0) continue;
                        verifyRc[i] = verify_preset_u16(dev, preset_fields[i].code, values[i]);
                    }
                }
            }

            print_preset_write_result(id, slot, slotSelRc, baselineReadRc, nameRequested, nameRc,
                                      preset_fields, requested, values, writeRc, verifyRc, fieldCount, wasEmptySlot);
            fflush(stdout);
            continue;
        }

        /* ── sleep ── */
        if (!strcmp(cmd, "sleep")) {
            int ms = json_get_int(line, "ms", 100);
            fprintf(stderr, "[HELPER] Sleeping %dms...\n", ms);
            usleep(ms * 1000);
            fprintf(stdout, "{\"id\":\"%s\",\"success\":true}\n",
                    json_get_string(line, "id") ? json_get_string(line, "id") : "0");
            fflush(stdout);
            continue;
        }

        /* ── test_vendor ── */
        if (!strcmp(cmd, "test_vendor")) {
            if (!dev) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"not_connected\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }
            const char *op = json_get_string(line, "op");
            uint16_t vendorCode = 0x902B;
            int cmdParamCount = 0;
            uint32_t cmdParams[5] = {0};
            const uint8_t *testData = NULL;
            uint32_t testDataLen = 0;
            int timeoutMs = 10000;

            if (op) {
                if (!strcmp(op, "tether_open")) {
                    vendorCode = 0x902B;
                    cmdParamCount = 1;
                    cmdParams[0] = 1;
                } else if (!strcmp(op, "send_object_info")) {
                    vendorCode = 0x900C;
                    cmdParamCount = 3;
                    cmdParams[0] = 0; cmdParams[1] = 0; cmdParams[2] = 0;
                    /* Minimal ObjectInfo for testing */
                    uint8_t minObjInfo[16];
                    memset(minObjInfo, 0, sizeof(minObjInfo));
                    put_u32_le(minObjInfo, 0);  /* StorageID */
                    put_u16_le(minObjInfo + 4, 0xF802);  /* ObjectFormat: RAF */
                    put_u16_le(minObjInfo + 6, 0);  /* ProtectionStatus */
                    put_u32_le(minObjInfo + 8, 0);  /* CompressedSize */
                    testData = minObjInfo;
                    testDataLen = 16;
                } else {
                    fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"unknown_vendor_op:%s\"}\n",
                            json_get_string(line, "id") ? json_get_string(line, "id") : "0", op);
                    fflush(stdout);
                    continue;
                }
            }

            /* Empty data for tether_open */
            if (!testData) {
                static uint8_t emptyData[1];
                testData = emptyData;
                testDataLen = 0;
            }

            int rc = send_vendor_command(dev, vendorCode, cmdParamCount, cmdParams, testData, testDataLen, timeoutMs);
            const char *status = "ok";
            if (rc == -100) status = "endpoint_stall_OUT";
            else if (rc == -101) status = "endpoint_stall_IN";
            else if (rc < 0 && rc > -100) status = "protocol_error";
            else if (rc > 0x2000) status = "camera_error";
            else if (rc != 0) status = "transfer_error";

            fprintf(stdout, "{\"id\":\"%s\",\"success\":%s,\"result\":{\"code\":\"0x%04X\",\"rc\":%d,\"status\":\"%s\"}}\n",
                    json_get_string(line, "id") ? json_get_string(line, "id") : "0",
                    rc == 0 ? "true" : "false",
                    vendorCode, rc, status);
            fflush(stdout);
            continue;
        }

        /* ── load_raf ── */
        if (!strcmp(cmd, "load_raf")) {
            if (!dev) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"not_connected\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }
            const char *filePath = json_get_string(line, "path");
            if (!filePath || strlen(filePath) == 0) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"missing_file_path\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }

            /* Read RAF file */
            FILE *f = fopen(filePath, "rb");
            if (!f) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"file_not_found\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }
            fseek(f, 0, SEEK_END);
            long fileSize = ftell(f);
            fseek(f, 0, SEEK_SET);
            uint8_t *rafData = (uint8_t *)malloc(fileSize);
            if (!rafData) {
                fclose(f);
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"out_of_memory\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }
            fread(rafData, 1, fileSize, f);
            fclose(f);
            uint32_t rafSize = (uint32_t)fileSize;
            fprintf(stderr, "[HELPER] RAF file: %s (%.1f MB)\n", filePath, rafSize / 1024.0 / 1024.0);

            /* Build ObjectInfo structure (matches FilmKit/rawji format exactly) */
            uint8_t objectInfo[256];
            memset(objectInfo, 0, sizeof(objectInfo));
            int off = 0;
            put_u32_le(objectInfo + off, 0); off += 4;          /* StorageID */
            put_u16_le(objectInfo + off, 0xF802); off += 2;    /* ObjectFormat: RAF */
            put_u16_le(objectInfo + off, 0); off += 2;         /* ProtectionStatus */
            put_u32_le(objectInfo + off, rafSize); off += 4;   /* CompressedSize */
            put_u16_le(objectInfo + off, 0); off += 2;         /* ThumbFormat */
            put_u32_le(objectInfo + off, 0); off += 4;         /* ThumbCompressedSize */
            put_u32_le(objectInfo + off, 0); off += 4;         /* ThumbPixWidth */
            put_u32_le(objectInfo + off, 0); off += 4;         /* ThumbPixHeight */
            put_u32_le(objectInfo + off, 0); off += 4;         /* ImagePixWidth */
            put_u32_le(objectInfo + off, 0); off += 4;         /* ImagePixHeight */
            put_u32_le(objectInfo + off, 0); off += 4;         /* ImageBitDepth */
            put_u32_le(objectInfo + off, 0); off += 4;         /* ParentObject */
            put_u16_le(objectInfo + off, 0); off += 2;         /* AssociationType */
            put_u32_le(objectInfo + off, 0); off += 4;         /* AssociationDesc */
            put_u32_le(objectInfo + off, 0); off += 4;         /* SequenceNumber */
            /* Filename: FUP_FILE.dat (PTP string: 1-byte char count + UCS-2LE) */
            const char *fname = "FUP_FILE.dat";
            uint8_t fnameLen = 12 + 1;  /* length including null terminator */
            objectInfo[off++] = fnameLen;
            for (int i = 0; i <= 12; i++) {
                uint16_t ch = (i < 12) ? (uint16_t)fname[i] : 0;
                put_u16_le(objectInfo + off, ch); off += 2;
            }
            /* CaptureDate, ModificationDate, Keywords (empty) */
            objectInfo[off++] = 0;  /* CaptureDate */
            objectInfo[off++] = 0;  /* ModificationDate */
            objectInfo[off++] = 0;  /* Keywords */
            uint32_t objectInfoLen = (uint32_t)off;
            fprintf(stderr, "[HELPER] ObjectInfo: %u bytes\n", objectInfoLen);

            /* Step 1: Send ObjectInfo via Fuji vendor command 0x900C */
            fprintf(stderr, "[HELPER] Sending ObjectInfo (0x900C)...\n");
            uint32_t infoParams[] = {0, 0, 0};  /* storage_id, handle, 0 */
            int rc = send_vendor_command(dev, 0x900C, 3, infoParams, objectInfo, objectInfoLen, 30000);
            if (rc != 0) {
                const char *stallMsg = rc == -100 ? "OUT endpoint stalled" :
                                       rc == -101 ? "IN endpoint stalled" :
                                       rc > 0x2000 ? "camera rejected" : "transfer failed";
                fprintf(stderr, "[HELPER] SendObjectInfo failed: rc=%d (%s)\n", rc, stallMsg);
                free(rafData);
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"result\":{\"error\":\"send_object_info_failed\",\"rc\":%d,\"detail\":\"%s\"}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0", rc, stallMsg);
                fflush(stdout);
                continue;
            }
            fprintf(stderr, "[HELPER] ObjectInfo sent OK\n");

            /* Step 2: Send RAF data via Fuji vendor command 0x900D */
            fprintf(stderr, "[HELPER] Sending RAF data (0x900D)...\n");
            rc = send_vendor_command(dev, 0x900D, 0, NULL, rafData, rafSize, 60000);
            free(rafData);
            if (rc != 0) {
                const char *stallMsg = rc == -100 ? "OUT endpoint stalled" :
                                       rc == -101 ? "IN endpoint stalled" :
                                       rc > 0x2000 ? "camera rejected" : "transfer failed";
                fprintf(stderr, "[HELPER] SendObject2 failed: rc=%d (%s)\n", rc, stallMsg);
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"result\":{\"error\":\"send_object_failed\",\"rc\":%d,\"detail\":\"%s\"}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0", rc, stallMsg);
                fflush(stdout);
                continue;
            }
            /*
             * Post-upload delay — give camera time to process the file.
             * FilmKit (X100VI tested) has no explicit delay but WebUSB
             * introduces natural latency. libusb is faster; the camera
             * may reject commands if sent too soon after upload.
             *
             * Previously: clear_endpoint_halt(0x81) + 100ms — this confused
             * the camera's state machine (DeviceBusy after upload).
             * Now: just wait, then reconnect handles endpoint recovery.
             */
            usleep(1000000);  /* 1s — let camera finish processing RAF */
            fprintf(stderr, "[HELPER] RAF data sent OK — file loaded\n");
            fprintf(stdout, "{\"id\":\"%s\",\"success\":true,\"result\":{\"status\":\"raf_loaded\",\"size\":%u}}\n",
                    json_get_string(line, "id") ? json_get_string(line, "id") : "0", rafSize);
            fflush(stdout);
            continue;
        }

        /* ── get_profile ── */
        if (!strcmp(cmd, "get_profile")) {
            if (!dev) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"not_connected\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }
            const char *outPath = json_get_string(line, "output");
            if (!outPath || strlen(outPath) == 0) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"missing_output_path\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }
            int rc = read_large_prop(dev, 0xD185, outPath);
            if (rc == 0) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":true,\"result\":{\"status\":\"profile_read\",\"path\":\"%s\"}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0", outPath);
            } else {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"result\":{\"error\":\"profile_read_failed\",\"rc\":%d}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0", rc);
            }
            fflush(stdout);
            continue;
        }

        /* ── set_profile ──
         * Write native profile (0xD185) from file. Used after read/modify.
         * The profile is ~625 bytes of raw binary data.
         */
        if (!strcmp(cmd, "set_profile")) {
            if (!dev) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"not_connected\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }
            const char *profPath = json_get_string(line, "path");
            if (!profPath || strlen(profPath) == 0) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"missing_path\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }

            FILE *f = fopen(profPath, "rb");
            if (!f) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"file_not_found\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }
            fseek(f, 0, SEEK_END);
            long profSize = ftell(f);
            fseek(f, 0, SEEK_SET);
            uint8_t *profData = (uint8_t *)malloc(profSize);
            fread(profData, 1, profSize, f);
            fclose(f);

            fprintf(stderr, "[PROFILE] Writing 0xD185 profile: %ld bytes\n", profSize);

            /* SetDevicePropValue: COMMAND */
            uint32_t setParam[] = {0xD185};
            int rc = ptp_send(dev, 0x1016, 1, setParam);
            if (rc != LIBUSB_SUCCESS) {
                free(profData);
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"result\":{\"error\":\"cmd_send_failed\",\"rc\":%d}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0", rc);
                fflush(stdout);
                continue;
            }

            /* DATA container with profile bytes */
            rc = ptp_send_data(dev, 0x1016, g_transactionId, profData, (uint32_t)profSize);
            free(profData);
            if (rc != LIBUSB_SUCCESS) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"result\":{\"error\":\"data_send_failed\",\"rc\":%d}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0", rc);
                fflush(stdout);
                continue;
            }

            /* RESPONSE */
            uint8_t resp[32]; int rlen = 0;
            usleep(10000);
            rc = ptp_recv(dev, resp, sizeof(resp), &rlen);
            if (rc != LIBUSB_SUCCESS || rlen < 12) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"result\":{\"error\":\"resp_failed\",\"rc\":%d}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0", rc);
                fflush(stdout);
                continue;
            }

            uint16_t respCode = resp[6] | (resp[7] << 8);
            if (respCode == 0x2001) {
                fprintf(stderr, "[PROFILE] Profile written successfully\n");
                fprintf(stdout, "{\"id\":\"%s\",\"success\":true,\"result\":{\"status\":\"profile_set\",\"bytes\":%ld}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0", profSize);
            } else {
                fprintf(stderr, "[PROFILE] Response 0x%04X\n", respCode);
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"result\":{\"error\":\"camera_rejected\",\"code\":\"0x%04X\"}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0", respCode);
            }
            fflush(stdout);
            continue;
        }

        /* ── trigger_conversion ── */
        if (!strcmp(cmd, "trigger_conversion")) {
            if (!dev) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"not_connected\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }
            int fullRes = json_get_int(line, "full_resolution", 1);
            /* X100VI always uses value=0 (FilmKit protocol), ignore fullRes param */
            (void)fullRes;
            int rc = trigger_conversion_with_baseline(dev);
            if (rc == 0) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":true,\"result\":{\"status\":\"conversion_started\",\"baseline_inventory\":\"captured\",\"baseline_handle_count\":%u}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0",
                        g_conversion_baseline.count);
            } else {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"result\":{\"error\":\"baseline_inventory_or_trigger_failed\",\"rc\":%d}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0", rc);
            }
            fflush(stdout);
            continue;
        }

        /* ── wait_result ── */
        if (!strcmp(cmd, "wait_result")) {
            if (!dev) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"not_connected\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }
            const char *outPath = json_get_string(line, "output");
            if (!outPath || strlen(outPath) == 0) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"missing_output_path\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }
            int timeoutMs = json_get_int(line, "timeout_ms", 30000);
            ConversionRetrieval retrieval = wait_for_result(dev, outPath, timeoutMs);
            fprintf(stdout,
                    "{\"id\":\"%s\",\"success\":%s,\"result\":{\"status\":\"%s\",\"path\":\"%s\","
                    "\"size\":%u,\"candidate_handle\":%u,\"candidate_format\":%u,"
                    "\"candidate_name\":\"%s\",\"diagnostics\":{\"baseline_handle_count\":%u,"
                    "\"post_handle_count\":%u,\"new_handle_count\":%u,\"inspected_object_count\":%u,"
                    "\"auto_deleted\":false,\"delivery_verified\":%s},\"rc\":%d}}\n",
                    json_get_string(line, "id") ? json_get_string(line, "id") : "0",
                    retrieval.downloaded ? "true" : "false", retrieval.state, outPath,
                    retrieval.candidate_size, retrieval.candidate_handle, retrieval.candidate_format,
                    retrieval.candidate_name, retrieval.baseline_count, retrieval.post_count,
                    retrieval.new_count, retrieval.inspected_count,
                    retrieval.downloaded ? "true" : "false", retrieval.rc);
            fflush(stdout);
            continue;
        }

        /* ── convert_raf ── */
        /* Full pipeline: load RAF → get profile → set profile → trigger → wait → done */
        if (!strcmp(cmd, "convert_raf")) {
            if (!dev) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"not_connected\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }
            const char *rafPath = json_get_string(line, "input");
            char rafPathBuf[512];
            snprintf(rafPathBuf, sizeof(rafPathBuf), "%s", rafPath ? rafPath : "");
            const char *jpegPath = json_get_string(line, "output");
            char jpegPathBuf[512];
            snprintf(jpegPathBuf, sizeof(jpegPathBuf), "%s", jpegPath ? jpegPath : "");
            if (strlen(rafPathBuf) == 0 || strlen(jpegPathBuf) == 0) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"missing_input_or_output\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }

            fprintf(stderr, "[PIPELINE] Starting RAF conversion: %s → %s\n", rafPathBuf, jpegPathBuf);

            /* Step 1: Load RAF */
            FILE *rafFile = fopen(rafPathBuf, "rb");
            if (!rafFile) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"file_not_found\"}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0");
                fflush(stdout);
                continue;
            }
            fseek(rafFile, 0, SEEK_END);
            long rafSizeLong = ftell(rafFile);
            fseek(rafFile, 0, SEEK_SET);
            uint32_t rafSize = (uint32_t)rafSizeLong;
            uint8_t *rafData = (uint8_t *)malloc(rafSize);
            fread(rafData, 1, rafSize, rafFile);
            fclose(rafFile);

            /* Build ObjectInfo (matches load_raf exactly — 82 bytes) */
            uint8_t objectInfo[256];
            memset(objectInfo, 0, sizeof(objectInfo));
            int off = 0;
            put_u32_le(objectInfo + off, 0); off += 4;          /* StorageID */
            put_u16_le(objectInfo + off, 0xF802); off += 2;    /* ObjectFormat: RAF */
            put_u16_le(objectInfo + off, 0); off += 2;         /* ProtectionStatus */
            put_u32_le(objectInfo + off, rafSize); off += 4;   /* CompressedSize */
            put_u16_le(objectInfo + off, 0); off += 2;         /* ThumbFormat */
            put_u32_le(objectInfo + off, 0); off += 4;         /* ThumbCompressedSize */
            put_u32_le(objectInfo + off, 0); off += 4;         /* ThumbPixWidth */
            put_u32_le(objectInfo + off, 0); off += 4;         /* ThumbPixHeight */
            put_u32_le(objectInfo + off, 0); off += 4;         /* ImagePixWidth */
            put_u32_le(objectInfo + off, 0); off += 4;         /* ImagePixHeight */
            put_u32_le(objectInfo + off, 0); off += 4;         /* ImageBitDepth */
            put_u32_le(objectInfo + off, 0); off += 4;         /* ParentObject */
            put_u16_le(objectInfo + off, 0); off += 2;         /* AssociationType */
            put_u32_le(objectInfo + off, 0); off += 4;         /* AssociationDesc */
            put_u32_le(objectInfo + off, 0); off += 4;         /* SequenceNumber */
            /* Filename: FUP_FILE.dat (PTP string: 1-byte char count + UCS-2LE) */
            const char *fname = "FUP_FILE.dat";
            uint8_t fnameLen = 12 + 1;  /* length including null terminator */
            objectInfo[off++] = fnameLen;
            for (int i = 0; i <= 12; i++) {
                uint16_t ch = (i < 12) ? (uint16_t)fname[i] : 0;
                put_u16_le(objectInfo + off, ch); off += 2;
            }
            /* CaptureDate, ModificationDate, Keywords (empty) */
            objectInfo[off++] = 0;  /* CaptureDate */
            objectInfo[off++] = 0;  /* ModificationDate */
            objectInfo[off++] = 0;  /* Keywords */
            uint32_t objectInfoLen = (uint32_t)off;

            /* Send ObjectInfo */
            fprintf(stderr, "[PIPELINE] Step 1: Send ObjectInfo...\n");
            uint32_t infoParams[] = {0, 0, 0};
            int rc = send_vendor_command(dev, 0x900C, 3, infoParams, objectInfo, objectInfoLen, 30000);
            if (rc != 0) {
                free(rafData);
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"result\":{\"error\":\"send_object_info_failed\",\"rc\":%d}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0", rc);
                fflush(stdout);
                continue;
            }

            /* Send RAF data */
            fprintf(stderr, "[PIPELINE] Step 2: Send RAF data...\n");
            rc = send_vendor_command(dev, 0x900D, 0, NULL, rafData, rafSize, 60000);
            free(rafData);
            if (rc != 0) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"result\":{\"error\":\"send_raf_failed\",\"rc\":%d}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0", rc);
                fflush(stdout);
                continue;
            }
            fprintf(stderr, "[PIPELINE] RAF loaded\n");

            /* ── Reconnect after large vendor transfer ──
             * macOS libusb IN endpoint breaks after 83MB vendor transfer.
             * Reconnect restores the USB stack. Camera state (loaded RAF)
             * persists across reconnections.
             * On Linux/WebUSB this is a no-op cost (~300ms) but necessary
             * for macOS compatibility.
             */
            fprintf(stderr, "[PIPELINE] Reconnecting after RAF upload...\n");
            do_close_device(&dev);
            usleep(2000000);  /* 2s — camera needs time after large transfer */
            rc = do_open_device(ctx, &dev);
            if (rc != 0) {
                const char *errMsg = rc == -1 ? "camera_not_found" : "interface_claim_failed";
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"result\":{\"error\":\"reconnect_%s\"}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0", errMsg);
                fflush(stdout);
                continue;
            }
            /* Settle delay after reconnect — camera needs time before accepting commands */
            usleep(2000000);  /* 2s settle after fresh connection */
            fprintf(stderr, "[PIPELINE] Reconnected (settled)\n");

            /* Step 3: Send default profile (can't read from camera on macOS after upload)
             * FilmKit/rawji: getProfile → setProfile → trigger
             * We build a valid default profile from scratch (rawji standard format) */
            fprintf(stderr, "[PIPELINE] Step 3: Send default profile...\n");
            rc = send_default_profile(dev);
            if (rc != 0) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"result\":{\"error\":\"set_profile_failed\",\"rc\":%d}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0", rc);
                fflush(stdout);
                continue;
            }

            /* Step 4: Trigger conversion (value=0 per FilmKit/X100VI) */
            fprintf(stderr, "[PIPELINE] Step 4: Trigger conversion...\n");
            rc = trigger_conversion_with_baseline(dev);
            if (rc != 0) {
                fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"result\":{\"error\":\"trigger_failed\",\"rc\":%d}}\n",
                        json_get_string(line, "id") ? json_get_string(line, "id") : "0", rc);
                fflush(stdout);
                continue;
            }

            /* Step 6: Wait for result (give camera a moment before first poll) */
            fprintf(stderr, "[PIPELINE] Step 6: Wait for JPEG...\n");
            usleep(2000000);  /* 2s — camera needs time to start processing */
            ConversionRetrieval retrieval = wait_for_result(dev, jpegPathBuf, 30000);
            fprintf(stdout,
                    "{\"id\":\"%s\",\"success\":%s,\"result\":{\"status\":\"%s\",\"path\":\"%s\","
                    "\"size\":%u,\"candidate_handle\":%u,\"candidate_format\":%u,"
                    "\"candidate_name\":\"%s\",\"diagnostics\":{\"baseline_handle_count\":%u,"
                    "\"post_handle_count\":%u,\"new_handle_count\":%u,\"inspected_object_count\":%u,"
                    "\"auto_deleted\":false,\"delivery_verified\":%s},\"rc\":%d}}\n",
                    json_get_string(line, "id") ? json_get_string(line, "id") : "0",
                    retrieval.downloaded ? "true" : "false", retrieval.state, jpegPathBuf,
                    retrieval.candidate_size, retrieval.candidate_handle, retrieval.candidate_format,
                    retrieval.candidate_name, retrieval.baseline_count, retrieval.post_count,
                    retrieval.new_count, retrieval.inspected_count,
                    retrieval.downloaded ? "true" : "false", retrieval.rc);
            fflush(stdout);
            continue;
        }

        /* ── exit ── */
        if (!strcmp(cmd, "exit")) {
            do_close_device(&dev);
            fprintf(stdout, "{\"id\":\"%s\",\"success\":true,\"result\":\"exiting\"}\n",
                    json_get_string(line, "id") ? json_get_string(line, "id") : "0");
            fflush(stdout);
            break;
        }

        /* Unknown command */
        fprintf(stdout, "{\"id\":\"%s\",\"success\":false,\"error\":\"unknown_command:%s\"}\n",
                json_get_string(line, "id") ? json_get_string(line, "id") : "0", cmd);
        fflush(stdout);
    }

    /* Cleanup */
    do_close_device(&dev);
    libusb_exit(ctx);
    return 0;
}
#endif
