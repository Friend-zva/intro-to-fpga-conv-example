#include <unistd.h>

#ifndef MAX_DMA_CTX_NUM
#define MAX_DMA_CTX_NUM 16
#endif

int dev_open(char *node);
int dev_close(int fd);

uint64_t request_mem(int fd, int index, uint32_t size);
void release_mem(int fd, int index);

void *mmap_mem(int fd, int index, size_t length);
void *mmap_bar(int fd, int index, size_t length);

void debug_dma(int fd, int index, uint32_t size);
