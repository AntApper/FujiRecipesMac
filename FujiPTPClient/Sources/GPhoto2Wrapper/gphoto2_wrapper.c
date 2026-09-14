#include "include/gphoto2_wrapper.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Camera lifecycle
int gphoto2_camera_new(void** camera) {
    Camera* cam = NULL;
    int result = gp_camera_new(&cam);
    if (result == GP_OK && camera != NULL) {
        *camera = cam;
    }
    return result;
}

void gphoto2_camera_free(void* camera) {
    if (camera != NULL) {
        gp_camera_free((Camera*)camera);
    }
}

int gphoto2_camera_init(void* camera, void* context) {
    return gp_camera_init((Camera*)camera, (GPContext*)context);
}

int gphoto2_camera_exit(void* camera, void* context) {
    return gp_camera_exit((Camera*)camera, (GPContext*)context);
}

int gphoto2_camera_get_config(void* camera, void** config, void* context) {
    CameraWidget* widget = NULL;
    int result = gp_camera_get_config((Camera*)camera, &widget, (GPContext*)context);
    if (result == GP_OK && config != NULL) {
        *config = widget;
    }
    return result;
}

int gphoto2_camera_set_config(void* camera, void* config, void* context) {
    return gp_camera_set_config((Camera*)camera, (CameraWidget*)config, (GPContext*)context);
}

int gphoto2_camera_get_about(void* camera, char* about, void* context) {
    CameraText text;
    memset(&text, 0, sizeof(text));
    int result = gp_camera_get_about((Camera*)camera, &text, (GPContext*)context);
    if (result == GP_OK && about != NULL) {
        strncpy(about, text.text, 4095);
        about[4095] = '\0';
    }
    return result;
}

int gphoto2_camera_get_abilities(void* camera, void* abilities) {
    return gp_camera_get_abilities((Camera*)camera, (CameraAbilities*)abilities);
}

int gphoto2_camera_set_port_info(void* camera, void* info) {
    return gp_camera_set_port_info((Camera*)camera, (GPPortInfo)info);
}

// Port info list
void* gphoto2_port_info_list_new(void) {
    GPPortInfoList* list = NULL;
    gp_port_info_list_new(&list);
    return list;
}

int gphoto2_port_info_list_count(void* list) {
    return gp_port_info_list_count((GPPortInfoList*)list);
}

int gphoto2_port_info_list_get_info(void* list, int index, void* info) {
    return gp_port_info_list_get_info((GPPortInfoList*)list, index, (GPPortInfo*)info);
}

void gphoto2_port_info_list_free(void* list) {
    gp_port_info_list_free((GPPortInfoList*)list);
}

// Widget functions
int gphoto2_widget_get_value(void* widget, void* value) {
    return gp_widget_get_value((CameraWidget*)widget, (void*)value);
}

int gphoto2_widget_get_type(void* widget, int32_t* type) {
    CameraWidgetType wtype = 0;
    int result = gp_widget_get_type((CameraWidget*)widget, &wtype);
    if (result == GP_OK && type != NULL) {
        *type = (int32_t)wtype;
    }
    return result;
}

int gphoto2_widget_count_choices(void* widget) {
    return gp_widget_count_choices((CameraWidget*)widget);
}

int gphoto2_widget_get_choice(void* widget, int index, const char** choice) {
    const char* c = NULL;
    int result = gp_widget_get_choice((CameraWidget*)widget, index, &c);
    if (result == GP_OK && choice != NULL) {
        *choice = c;
    }
    return result;
}

int gphoto2_widget_get_child_by_name(void* widget, const char* name, void** child) {
    CameraWidget* c = NULL;
    int result = gp_widget_get_child_by_name((CameraWidget*)widget, name, &c);
    if (result == GP_OK && child != NULL) {
        *child = c;
    }
    return result;
}

// Port operations
int gphoto2_port_open(void* port) {
    return gp_port_open((GPPort*)port);
}

void gphoto2_port_close(void* port) {
    gp_port_close((GPPort*)port);
}

// Context
void* gphoto2_context_new(void) {
    GPContext* ctx = gp_context_new();
    return ctx;
}

// Port operations (legacy API)
int gphoto2_port_send_scsi_cmd(void* port, int to_dev,
                               char* cmd, int cmd_size,
                               char* sense, int sense_size,
                               char* data, int data_size) {
    return gp_port_send_scsi_cmd((GPPort*)port, to_dev, cmd, cmd_size, sense, sense_size, data, data_size);
}

// Widget set value
int gphoto2_widget_set_value(void* widget, const char* value) {
    if (!widget || !value) return GP_ERROR_BAD_PARAMETERS;
    return gp_widget_set_value((CameraWidget*)widget, (void*)value);
}

// Helper: get a widget by path (e.g., "/main/settings/preset_slot")
static CameraWidget* get_widget_by_path(CameraWidget* root, const char* path) {
    if (!root || !path) return NULL;
    
    // Skip leading slash
    if (*path == '/') path++;
    
    CameraWidget* current = root;
    char pathCopy[256];
    strncpy(pathCopy, path, sizeof(pathCopy) - 1);
    pathCopy[sizeof(pathCopy) - 1] = '\0';
    
    // Split path by / and traverse
    char* token = strtok(pathCopy, "/");
    while (token) {
        CameraWidget* child = NULL;
        int result = gp_widget_get_child_by_name(current, token, &child);
        if (result != GP_OK || !child) return NULL;
        current = child;
        token = strtok(NULL, "/");
    }
    
    return current;
}

// Read config value by path
int gphoto2_get_config_value(void* camera, void* context, const char* path, char* value, int value_size) {
    if (!camera || !path || !value || value_size <= 0) return GP_ERROR_BAD_PARAMETERS;
    
    CameraWidget* config = NULL;
    int result = gp_camera_get_config((Camera*)camera, &config, (GPContext*)context);
    if (result != GP_OK) return result;
    
    CameraWidget* widget = get_widget_by_path(config, path);
    if (!widget) {
        gp_widget_unref(config);
        return GP_ERROR_NO_MEMORY;  // Widget not found
    }
    
    const char* val = NULL;
    result = gp_widget_get_value(widget, (void*)&val);
    if (result != GP_OK) {
        gp_widget_unref(config);
        return result;
    }
    
    if (val) {
        strncpy(value, val, value_size - 1);
        value[value_size - 1] = '\0';
    } else {
        value[0] = '\0';
    }
    
    gp_widget_unref(config);
    return GP_OK;
}

// Set config value by path
int gphoto2_set_config_value(void* camera, void* context, const char* path, const char* value) {
    if (!camera || !path || !value) return GP_ERROR_BAD_PARAMETERS;
    
    CameraWidget* config = NULL;
    int result = gp_camera_get_config((Camera*)camera, &config, (GPContext*)context);
    if (result != GP_OK) return result;
    
    CameraWidget* widget = get_widget_by_path(config, path);
    if (!widget) {
        gp_widget_unref(config);
        return GP_ERROR_NO_MEMORY;  // Widget not found
    }
    
    // Determine widget type and convert value accordingly
    CameraWidgetType type = 0;
    result = gp_widget_get_type(widget, &type);
    if (result != GP_OK) {
        gp_widget_unref(config);
        return result;
    }
    
    switch (type) {
        case GP_WIDGET_MENU:
        case GP_WIDGET_RADIO: {
            // For menu/radio widgets, try setting as string first
            result = gp_widget_set_value(widget, (void*)value);
            break;
        }
        case GP_WIDGET_RANGE: {
            // For range widgets, convert string to float
            char* endptr = NULL;
            float fval = strtof(value, &endptr);
            if (endptr == value) {
                gp_widget_unref(config);
                return GP_ERROR_BAD_PARAMETERS;  // Invalid number
            }
            result = gp_widget_set_value(widget, &fval);
            break;
        }
        case GP_WIDGET_TEXT: {
            // For text widgets, use string directly
            result = gp_widget_set_value(widget, (void*)value);
            break;
        }
        case GP_WIDGET_TOGGLE: {
            // For toggle widgets, convert to int (0 or 1)
            int ival = (strcmp(value, "0") != 0 && strcmp(value, "false") != 0) ? 1 : 0;
            result = gp_widget_set_value(widget, &ival);
            break;
        }
        default: {
            // Try string as fallback
            result = gp_widget_set_value(widget, (void*)value);
            break;
        }
    }
    
    if (result != GP_OK) {
        gp_widget_unref(config);
        return result;
    }
    
    result = gp_camera_set_config((Camera*)camera, config, (GPContext*)context);
    gp_widget_unref(config);
    return result;
}
