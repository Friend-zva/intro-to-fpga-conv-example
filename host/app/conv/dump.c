#include <stdio.h>

#include "dump.h"

static const int SIZE_DUMP = 32;

void dump_source(uint64_t sa, volatile uint8_t *sp) {
    printf("0x%016lx : ", sa);
    for (int i = 0; i < SIZE_DUMP; i++) {
        uint8_t r = sp[i * 4 + 0];
        uint8_t g = sp[i * 4 + 1];
        uint8_t b = sp[i * 4 + 2];
        uint8_t x = sp[i * 4 + 3];
        printf("(r=%02x g=%02x b=%02x x=%02x) ", r, g, b, x);
    }
    printf("\n");
}

void dump_destination(uint64_t da, volatile uint8_t *dp) {
    printf("0x%016lx : ", da);
    for (int i = 0; i < SIZE_DUMP; i++) {
        uint8_t p0 = dp[i * 4 + 0];
        uint8_t p1 = dp[i * 4 + 1];
        uint8_t p2 = dp[i * 4 + 2];
        uint8_t p3 = dp[i * 4 + 3];
        printf("(%02x %02x %02x %02x) ", p0, p1, p2, p3);
    }
    printf("\n");
}
