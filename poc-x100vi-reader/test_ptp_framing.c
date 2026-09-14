#define PTP_FRAME_FIXTURE_TEST
#include "x100vi_helper.c"

#include <assert.h>

typedef struct {
    const uint8_t *bytes;
    size_t length;
    size_t offset;
    size_t maximumChunk;
} FixtureStream;

static int fixture_read(void *context, uint8_t *buffer, size_t length,
                        size_t *transferred) {
    FixtureStream *stream = context;
    size_t remaining = stream->length - stream->offset;
    size_t count = length < remaining ? length : remaining;
    if (count > stream->maximumChunk) count = stream->maximumChunk;
    memcpy(buffer, stream->bytes + stream->offset, count);
    stream->offset += count;
    *transferred = count;
    return LIBUSB_SUCCESS;
}

static void append_header(uint8_t *buffer, uint32_t length, uint16_t type,
                          uint16_t code, uint32_t transactionId) {
    put_u32_le(buffer, length);
    put_u16_le(buffer + 4, type);
    put_u16_le(buffer + 6, code);
    put_u32_le(buffer + 8, transactionId);
}

static PtpContainer handles_container(uint32_t count, const uint32_t *handles) {
    PtpContainer data = {0};
    data.payloadLength = 4 + count * 4;
    data.payload = malloc(data.payloadLength);
    assert(data.payload);
    put_u32_le(data.payload, count);
    for (uint32_t i = 0; i < count; i++) {
        put_u32_le(data.payload + 4 + i * 4, handles[i]);
    }
    return data;
}

static void test_handle_payloads(void) {
    const uint8_t *parsed = NULL;
    uint32_t count = 0;
    PtpContainer zero = handles_container(0, NULL);
    assert(ptp_parse_object_handles(&zero, &parsed, &count) == LIBUSB_SUCCESS);
    assert(count == 0);
    ptp_container_free(&zero);

    uint32_t oneValue[] = {0x11223344};
    PtpContainer one = handles_container(1, oneValue);
    assert(ptp_parse_object_handles(&one, &parsed, &count) == LIBUSB_SUCCESS);
    assert(count == 1 && get_u32_le(parsed) == oneValue[0]);
    ptp_container_free(&one);

    uint32_t multipleValues[] = {1, 0x10203040, 0xFFFFFFFF};
    PtpContainer multiple = handles_container(3, multipleValues);
    assert(ptp_parse_object_handles(&multiple, &parsed, &count) == LIBUSB_SUCCESS);
    assert(count == 3 && get_u32_le(parsed + 8) == multipleValues[2]);
    ptp_container_free(&multiple);
}

static void test_fragmented_data_then_response(void) {
    uint8_t frames[32] = {0};
    append_header(frames, 20, 0x0002, 0x1007, 42);
    put_u32_le(frames + 12, 1);
    put_u32_le(frames + 16, 0xAABBCCDD);
    append_header(frames + 20, 12, 0x0003, 0x2001, 42);
    FixtureStream stream = {frames, sizeof(frames), 0, 3};

    PtpContainer data;
    assert(ptp_read_container_with(fixture_read, &stream, &data) == LIBUSB_SUCCESS);
    assert(ptp_validate_container(&data, 0x0002, 0x1007, 42) == LIBUSB_SUCCESS);
    assert(data.payloadLength == 8);
    const uint8_t *handles = NULL;
    uint32_t count = 0;
    assert(ptp_parse_object_handles(&data, &handles, &count) == LIBUSB_SUCCESS);
    assert(count == 1 && get_u32_le(handles) == 0xAABBCCDD);
    ptp_container_free(&data);

    PtpContainer response;
    assert(ptp_read_container_with(fixture_read, &stream, &response) == LIBUSB_SUCCESS);
    assert(ptp_validate_container(&response, 0x0003, 0x2001, 42) == LIBUSB_SUCCESS);
    assert(stream.offset == sizeof(frames));
    ptp_container_free(&response);
}

static void test_malformed_length(void) {
    uint8_t header[12] = {0};
    append_header(header, 11, 0x0002, 0x1007, 1);
    FixtureStream stream = {header, sizeof(header), 0, sizeof(header)};
    PtpContainer container;
    assert(ptp_read_container_with(fixture_read, &stream, &container) ==
           PTP_FRAME_INVALID_LENGTH);
}

static void test_session_response_validation_and_transport_reset(void) {
    PtpContainer response = {
        .length = 12,
        .type = 0x0003,
        .code = 0x2001,
        .transactionId = 1
    };
    assert(ptp_validate_container(&response, 0x0003, 0x2001, 1) == LIBUSB_SUCCESS);

    response.type = 0x0002;
    assert(ptp_validate_container(&response, 0x0003, 0x2001, 1) ==
           PTP_FRAME_INVALID_TYPE);
    response.type = 0x0003;
    response.code = 0x2003;
    assert(ptp_validate_container(&response, 0x0003, 0x2001, 1) ==
           PTP_FRAME_INVALID_CODE);
    response.code = 0x2001;
    response.transactionId = 2;
    assert(ptp_validate_container(&response, 0x0003, 0x2001, 1) ==
           PTP_FRAME_INVALID_TRANSACTION);

    g_sessionOpen = true;
    g_transactionId = 27;
    g_ptpRxLength = 8;
    ptp_reset_transport_state();
    assert(!g_sessionOpen);
    assert(g_transactionId == 0);
    assert(g_ptpRxLength == 0);
}

int main(void) {
    test_handle_payloads();
    test_fragmented_data_then_response();
    test_malformed_length();
    test_session_response_validation_and_transport_reset();
    puts("PTP framing fixture tests passed");
    return 0;
}
