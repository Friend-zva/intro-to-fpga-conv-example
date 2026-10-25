#include <stdlib.h>
#include <string.h>

#include "config.h"

static const int SIZE_BLOCK_MIN = 128;
static const int SIZE_DATA_MAX = 4194304;

static const int WIDTH_IMAGE_MAX = 640;
static const int HEIGHT_IMAGE_MIN = 3;
static const int SIZE_KERNEL_MIN = 3;

Config init_config(int argc, char *argv[], int size_pixel) {
    int width_image = 256;
    int height_image = 8;
    int size_kernel = 3;
    int size_block = SIZE_BLOCK_MIN;
    int en_dumping = 0;

    if (argc > 1) {
        width_image = strtol(argv[1], NULL, 0);

        if (width_image > WIDTH_IMAGE_MAX) {
            width_image = WIDTH_IMAGE_MAX;
        }
    }
    if (argc > 2) {
        height_image = strtol(argv[2], NULL, 0);

        if (height_image < HEIGHT_IMAGE_MIN) {
            height_image = HEIGHT_IMAGE_MIN;
        }
    }
    int size_data = width_image * height_image * size_pixel;
    if (size_data < SIZE_BLOCK_MIN || size_data > SIZE_DATA_MAX) {
        width_image = WIDTH_IMAGE_MAX;
        height_image = SIZE_DATA_MAX / (size_pixel * WIDTH_IMAGE_MAX);
        size_data = width_image * height_image * size_pixel;
    }

    if (argc > 3) {
        size_kernel = strtol(argv[3], NULL, 0);

        if (size_kernel < SIZE_KERNEL_MIN) {
            size_kernel = SIZE_KERNEL_MIN;
        }
    }
    if (argc > 4) {
        size_block = strtol(argv[4], NULL, 0);
        if (size_block < SIZE_BLOCK_MIN) {
            size_block = SIZE_BLOCK_MIN;
        } else {
            size_block = ROUND2_TO(size_block, 32);
        }

        if (size_block > size_data) {
            size_block = size_data;
        }
    }
    if (argc > 5) {
        if (!strcmp(argv[5], "y") || !strcmp(argv[5], "1")) {
            en_dumping = 1;
        }
    }

    return (Config){.width_image = (uint32_t)width_image,
                    .height_image = (uint32_t)height_image,
                    .size_data = (uint32_t)size_data,
                    .size_kernel = (uint32_t)size_kernel,
                    .size_block = (uint32_t)size_block,
                    .en_dumping = en_dumping};
}
