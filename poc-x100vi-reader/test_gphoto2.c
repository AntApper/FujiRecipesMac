#include <stdio.h>
#include <stdlib.h>
#include <gphoto2/gphoto2-camera.h>
#include <gphoto2/gphoto2-port.h>

int main(int argc, char **argv) {
    GPContext *context;
    Camera *camera;
    CameraList *list;
    int result;
    
    /* Initialize */
    result = gp_camera_new(&camera);
    if (result != GP_OK) {
        fprintf(stderr, "Error creating camera: %s\n", gp_result_as_string(result));
        return 1;
    }
    
    context = gp_context_new();
    if (!context) {
        fprintf(stderr, "Error creating context\n");
        return 1;
    }
    
    list = gp_list_new();
    if (!list) {
        fprintf(stderr, "Error creating list\n");
        return 1;
    }
    
    /* Detect camera */
    fprintf(stderr, "Detecting camera...\n");
    result = gp_camera_autodetect(list, context);
    if (result != GP_OK) {
        fprintf(stderr, "Error detecting camera: %s\n", gp_result_as_string(result));
        gp_list_free(list);
        gp_camera_free(camera);
        return 1;
    }
    
    /* Set port info from list */
    const char *path = gp_list_get_name(list, 0);
    fprintf(stderr, "Camera path: %s\n", path);
    GPPortInfo info;
    gp_port_info_new(&info);
    gp_port_info_set_path(info, path);
    gp_camera_set_port_info(camera, info);
    
    /* Initialize camera */
    fprintf(stderr, "Initializing camera...\n");
    result = gp_camera_init(camera, context);
    if (result != GP_OK) {
        fprintf(stderr, "Error initializing camera: %s\n", gp_result_as_string(result));
        gp_list_free(list);
        gp_camera_free(camera);
        return 1;
    }
    
    /* Try to upload a file */
    fprintf(stderr, "Uploading test file...\n");
    CameraFilePath filepath;
    result = gp_camera_file_upload(camera, GP_FILE_TYPE_NORMAL, 
                                    "/tmp/test.raf", "DSCF0001.RAF", context);
    if (result != GP_OK) {
        fprintf(stderr, "Error uploading file: %s\n", gp_result_as_string(result));
    } else {
        fprintf(stderr, "File uploaded successfully!\n");
    }
    
    /* Cleanup */
    gp_camera_exit(camera, context);
    gp_list_free(list);
    gp_camera_free(camera);
    gp_context_unref(context);
    
    return (result == GP_OK) ? 0 : 1;
}
