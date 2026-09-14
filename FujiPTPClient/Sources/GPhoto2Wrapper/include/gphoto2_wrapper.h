#ifndef GPHOTO2_WRAPPER_H
#define GPHOTO2_WRAPPER_H

#include <stdint.h>
#include <stdbool.h>
#include <gphoto2/gphoto2.h>

#ifdef __cplusplus
extern "C" {
#endif

// Camera lifecycle
int gphoto2_camera_new(void** camera);
void gphoto2_camera_free(void* camera);
int gphoto2_camera_init(void* camera, void* context);
int gphoto2_camera_exit(void* camera, void* context);
int gphoto2_camera_get_config(void* camera, void** config, void* context);
int gphoto2_camera_set_config(void* camera, void* config, void* context);
int gphoto2_camera_get_about(void* camera, char* about, void* context);
int gphoto2_camera_get_abilities(void* camera, void* abilities);
int gphoto2_camera_set_port_info(void* camera, void* info);

// Port info list
void* gphoto2_port_info_list_new(void);
int gphoto2_port_info_list_count(void* list);
int gphoto2_port_info_list_get_info(void* list, int index, void* info);
void gphoto2_port_info_list_free(void* list);

// Widget functions
int gphoto2_widget_get_value(void* widget, void* value);
int gphoto2_widget_get_type(void* widget, int32_t* type);
int gphoto2_widget_count_choices(void* widget);
int gphoto2_widget_get_choice(void* widget, int index, const char** choice);
int gphoto2_widget_get_child_by_name(void* widget, const char* name, void** child);
int gphoto2_widget_set_value(void* widget, const char* value);

// Config value read/write by path
int gphoto2_get_config_value(void* camera, void* context, const char* path, char* value, int value_size);
int gphoto2_set_config_value(void* camera, void* context, const char* path, const char* value);

// Port operations
int gphoto2_port_open(void* port);
void gphoto2_port_close(void* port);

// Context
void* gphoto2_context_new(void);

// Port operations (legacy API)
int gphoto2_port_send_scsi_cmd(void* port, int to_dev,
                               char* cmd, int cmd_size,
                               char* sense, int sense_size,
                               char* data, int data_size);

#ifdef __cplusplus
}
#endif

#endif /* GPHOTO2_WRAPPER_H */
