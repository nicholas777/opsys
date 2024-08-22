#include "libc_base.h"

void *
memset(void *start, int c, size_t count) {
    uint8_t *ptr = (uint8_t*)start;
    size_t end = (size_t)start + count;

    for (size_t i = 0; i < end; i++) {
        *ptr = (uint8_t)c;
    }

    return start;
}

int
memcmp(const void *ptr1, const void *ptr2, size_t n) {
    for (size_t i = 0; i < n; i++) {
        if (*(uint8_t*)ptr1 < *(uint8_t*)ptr2) return -1;
        else if (*(uint8_t*)ptr1 > *(uint8_t*)ptr2) return 1;
    }

    return 0;
}

void *
memcpy(void *dest, void *src, size_t n) {
    uint8_t *s = (uint8_t*)src;
    uint8_t *d = (uint8_t*)dest;

    for (size_t i = 0; i < n; i++) {
        d[i] = s[i];
    }
}

size_t
strlen(const char *str) {
    size_t i = 0;
    while (*str++ != 0)
        i++;

    return i;
}
