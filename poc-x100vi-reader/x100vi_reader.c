/*
 * x100vi_reader.c - v11
 *
 * Uses libusb to send PTP containers via bulk transfer to X100VI.
 * Bypasses SCSI commands and uses native PTP container format.
 *
 * Build: gcc -o x100vi_reader x100vi_reader.c -I/opt/homebrew/Cellar/libusb/1.0.30/include -L/opt/homebrew/lib -lusb-1.0
 * Run:   sudo ./x100vi_reader
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <libusb-1.0/libusb.h>

#define FUJI_VENDOR  0x04CB
#define X100VI_PRODUCT 0x0305

typedef struct { uint16_t code; const char *name; const char *key; } Prop;

static const Prop preset_props[] = {
    {0xD18C,"Preset Slot","slot"}, {0xD18D,"Preset Name","name"},
    {0xD18E,"Image Size","image_size"}, {0xD18F,"Image Quality","image_quality"},
    {0xD190,"Dynamic Range","dynamic_range"}, {0xD191,"Unknown D191","unknown_d191"},
    {0xD192,"Film Simulation","film_simulation"}, {0xD193,"Mono Warm/Cool","mono_warm_cool"},
    {0xD194,"Mono Mag/Green","mono_magenta_green"}, {0xD195,"Grain Effect","grain_effect"},
    {0xD196,"Color Chrome","color_chrome"}, {0xD197,"Color Chrome FX Blue","color_chrome_fxb"},
    {0xD198,"Smooth Skin","smooth_skin"}, {0xD199,"White Balance","white_balance"},
    {0xD19A,"WB Shift Red","wb_shift_r"}, {0xD19B,"WB Shift Blue","wb_shift_b"},
    {0xD19C,"Color Temp (K)","color_temp"}, {0xD19D,"Highlight Tone","highlight"},
    {0xD19E,"Shadow Tone","shadow"}, {0xD19F,"Color","color"},
    {0xD1A0,"Sharpness","sharpness"}, {0xD1A1,"High ISO NR","high_iso_nr"},
    {0xD1A2,"Clarity","clarity"}, {0xD1A3,"Long Exp NR","long_exp_nr"},
    {0xD1A4,"Color Space","color_space"}, {0xD1A5,"Unknown D1A5","unknown_d1a5"},
    {0, NULL, NULL}
};

static const Prop active_props[] = {
    {0xD001,"Film Simulation","film_simulation"}, {0xD007,"Dynamic Range","dynamic_range"},
    {0x5005,"White Balance","white_balance"}, {0xD023,"Grain Effect","grain_effect"},
    {0xD002,"Color","color"}, {0xD00B,"WB Shift Red","wb_shift_r"},
    {0xD00C,"WB Shift Blue","wb_shift_b"}, {0xD017,"Color Temp (K)","color_temp"},
    {0xD185,"Native Profile","native_profile"}, {0xD20B,"Device Name","device_name"},
    {0xD242,"Battery Level","battery_level"},
    {0, NULL, NULL}
};

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
    static const char *n[] = {"OFF","WEAK_SMALL","STRONG_SMALL","WEAK_LARGE","STRONG_LARGE"};
    return (v<=4) ? n[v] : NULL;
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
    if (!strcmp(key,"color_chrome")||!strcmp(key,"color_chrome_fxb")||!strcmp(key,"smooth_skin")) return r_chrome(v);
    if (!strcmp(key,"white_balance")) return r_wb(v);
    return NULL;
}

/* Send PTP container via bulk transfer */
static int ptp_send(libusb_device_handle *dev, uint16_t code, uint32_t p1, uint32_t p2, uint32_t p3) {
    uint8_t buf[32] = {0};
    /* Type: 0x0101 (request) */
    buf[0] = 0x01; buf[1] = 0x01;
    /* Code */
    buf[2] = (code >> 8) & 0xFF; buf[3] = code & 0xFF;
    /* TransactionID: 1 */
    buf[4] = 0; buf[5] = 0; buf[6] = 0; buf[7] = 1;
    /* Params */
    buf[8] = (p1 >> 24) & 0xFF; buf[9] = (p1 >> 16) & 0xFF;
    buf[10] = (p1 >> 8) & 0xFF; buf[11] = p1 & 0xFF;
    buf[12] = (p2 >> 24) & 0xFF; buf[13] = (p2 >> 16) & 0xFF;
    buf[14] = (p2 >> 8) & 0xFF; buf[15] = p2 & 0xFF;
    buf[16] = (p3 >> 24) & 0xFF; buf[17] = (p3 >> 16) & 0xFF;
    buf[18] = (p3 >> 8) & 0xFF; buf[19] = p3 & 0xFF;
    /* Length: header(12) + 3 params(12) + data(0) + length(4) = 28 */
    int totalLen = 2 + 2 + 4 + 12 + 0 + 4;
    buf[20] = (totalLen >> 24) & 0xFF; buf[21] = (totalLen >> 16) & 0xFF;
    buf[22] = (totalLen >> 8) & 0xFF; buf[23] = totalLen & 0xFF;

    int transferred = 0;
    return libusb_bulk_transfer(dev, 0x01, buf, 24, &transferred, 5000);
}

/* Read PTP response via bulk transfer */
static int ptp_recv(libusb_device_handle *dev, uint8_t *resp, int maxlen, int *outlen) {
    int total = 0;
    while (total < maxlen) {
        int transferred = 0;
        int rc = libusb_bulk_transfer(dev, 0x81, resp + total, maxlen - total, &transferred, 5000);
        if (rc != LIBUSB_SUCCESS) return rc;
        total += transferred;
        if (total >= 12) break; /* At least PTP response header */
    }
    *outlen = total;
    return LIBUSB_SUCCESS;
}

/* Read property value via PTP GetDevicePropData */
static int read_prop(libusb_device_handle *dev, uint16_t prop, uint32_t *val) {
    uint8_t resp[256]; int len = 0;

    /* Send GetDevicePropData (0x100E) with property code */
    int rc = ptp_send(dev, 0x100E, prop, 0, 0);
    if (rc != LIBUSB_SUCCESS) return -1;

    /* Read response */
    rc = ptp_recv(dev, resp, sizeof(resp), &len);
    if (rc != LIBUSB_SUCCESS) return -1;
    if (len < 12) return -2;

    uint16_t ptp_code = (resp[0] << 8) | resp[1];
    if (ptp_code == 0x2001 && len >= 12) {
        *val = (resp[8]<<24) | (resp[9]<<16) | (resp[10]<<8) | resp[11];
        return 0;
    }
    if (ptp_code == 0x2002) return -2;
    return -3;
}

int main(int argc, char *argv[]) {
    libusb_context *ctx = NULL;
    libusb_device_handle *dev = NULL;
    int rc;

    printf("X100VI Preset Slot Reader POC v11 (PTP bulk)\n");
    printf("=============================================\n\n");

    rc = libusb_init(&ctx);
    if (rc != LIBUSB_SUCCESS) {
        fprintf(stderr, "libusb_init failed: %s\n", libusb_error_name(rc));
        return 1;
    }
    libusb_set_debug(ctx, LIBUSB_LOG_LEVEL_WARNING);

    printf("Finding Fuji X100VI...\n");
    dev = libusb_open_device_with_vid_pid(ctx, FUJI_VENDOR, X100VI_PRODUCT);
    if (!dev) {
        fprintf(stderr, "❌ X100VI not found.\n");
        libusb_exit(ctx);
        return 1;
    }
    printf("✅ Found device\n");

    /* Get device info */
    struct libusb_device_descriptor desc;
    if (libusb_get_device_descriptor(libusb_get_device(dev), &desc) == LIBUSB_SUCCESS) {
        char vendor[256]={0}, product[256]={0}, serial[256]={0};
        libusb_get_string_descriptor_ascii(dev, desc.iManufacturer, (unsigned char*)vendor, sizeof(vendor));
        libusb_get_string_descriptor_ascii(dev, desc.iProduct, (unsigned char*)product, sizeof(product));
        libusb_get_string_descriptor_ascii(dev, desc.iSerialNumber, (unsigned char*)serial, sizeof(serial));
        printf("  Vendor: %s\n  Product: %s\n  Serial: %s\n\n", vendor, product, serial);
    }

    /* Get config descriptor */
    printf("USB Configuration:\n");
    struct libusb_config_descriptor *config = NULL;
    if (libusb_get_active_config_descriptor(libusb_get_device(dev), &config) == LIBUSB_SUCCESS) {
        for (int i = 0; i < config->bNumInterfaces; i++) {
            const struct libusb_interface_descriptor *iface = &config->interface[i].altsetting[0];
            printf("  Interface %d: class=0x%02X sub=0x%02X prot=0x%02X\n",
                   i, iface->bInterfaceClass, iface->bInterfaceSubClass, iface->bInterfaceProtocol);
            for (int j = 0; j < iface->bNumEndpoints; j++) {
                const struct libusb_endpoint_descriptor *ep = &iface->endpoint[j];
                printf("    EP 0x%02X: type=%d dir=%s max=%d\n",
                       ep->bEndpointAddress, ep->bmAttributes & 0x03,
                       (ep->bEndpointAddress & 0x80) ? "IN" : "OUT", ep->wMaxPacketSize);
            }
        }
        libusb_free_config_descriptor(config);
    }
    printf("\n");

    /* Prepare USB connection */
    printf("Preparing connection...\n");
    libusb_detach_kernel_driver(dev, 0);
    rc = libusb_set_configuration(dev, 1);
    rc = libusb_claim_interface(dev, 0);
    if (rc != LIBUSB_SUCCESS) {
        fprintf(stderr, "❌ Failed to claim interface: %s\n", libusb_error_name(rc));
        libusb_close(dev); libusb_exit(ctx);
        return 1;
    }
    printf("✅ Connected\n\n");

    /* Test: Send PTP GetDeviceInfo */
    printf("Testing PTP GetDeviceInfo...\n");
    uint8_t resp[256]; int len = 0;
    rc = ptp_send(dev, 0x1001, 0, 0, 0);
    if (rc == LIBUSB_SUCCESS) {
        rc = ptp_recv(dev, resp, sizeof(resp), &len);
        if (rc == LIBUSB_SUCCESS && len >= 2) {
            uint16_t code = (resp[0] << 8) | resp[1];
            printf("  Response: code=0x%04X, len=%d\n", code, len);
            printf("  Data: ");
            for (int i = 0; i < len && i < 32; i++) printf("%02X ", resp[i]);
            printf("\n");
        } else {
            printf("  No response (rc=%d, len=%d)\n", rc, len);
        }
    } else {
        printf("  Send failed: %s\n", libusb_error_name(rc));
    }
    printf("\n");

    /* Read active properties */
    printf("--- Active Properties ---\n");
    int act_ok = 0;
    for (int i = 0; active_props[i].code; i++) {
        uint32_t val = 0;
        rc = read_prop(dev, active_props[i].code, &val);
        const char *r = resolve(active_props[i].key, val);
        printf("  0x%04X %-20s: rc=%2d", active_props[i].code, active_props[i].name, rc);
        if (rc == 0) { printf(" val=%-10u %s", val, r ? r : ""); act_ok++; }
        printf("\n");
    }
    printf("Readable: %d/%d\n\n", act_ok, (int)(sizeof(active_props)/sizeof(active_props[0])-1));

    /* Read preset properties */
    printf("--- Preset Slot Properties ---\n");
    printf("%-8s %-25s %5s %12s %s\n", "Code", "Name", "RC", "Value", "Display");
    printf("---\n");
    int pr_ok = 0;
    for (int i = 0; preset_props[i].code; i++) {
        uint32_t val = 0;
        rc = read_prop(dev, preset_props[i].code, &val);
        const char *r = resolve(preset_props[i].key, val);
        printf("0x%04X  %-25s %5d", preset_props[i].code, preset_props[i].name, rc);
        if (rc == 0) { printf(" %12u %s", val, r ? r : ""); pr_ok++; }
        else printf(" (err)");
        printf("\n");
    }
    printf("Readable: %d/%d\n\n", pr_ok, (int)(sizeof(preset_props)/sizeof(preset_props[0])-1));

    /* JSON output */
    printf("--- JSON ---\n{\n  \"preset_properties\": {\n");
    bool first = true;
    for (int i = 0; preset_props[i].code; i++) {
        if (!first) printf(",\n");
        first = false;
        uint32_t val = 0;
        rc = read_prop(dev, preset_props[i].code, &val);
        printf("    \"0x%04X_%s\": { \"rc\": %d, \"raw\": %u", preset_props[i].code, preset_props[i].name, rc, val);
        if (rc == 0 && resolve(preset_props[i].key, val))
            printf(", \"display\": \"%s\"", resolve(preset_props[i].key, val));
        printf(" }");
    }
    printf("\n  }\n}\n");

    /* Cleanup */
    libusb_release_interface(dev, 0);
    libusb_close(dev);
    libusb_exit(ctx);

    printf("\nResult: %d/%d preset properties readable\n", pr_ok,
           (int)(sizeof(preset_props)/sizeof(preset_props[0])-1));
    if (pr_ok > 0) printf("✅ SUCCESS!\n");
    else printf("⚠️  No preset properties readable\n");

    return 0;
}
