#include <stdint.h>
#include <stddef.h>

void *
memset(void *start, int c, size_t count);

void *
memcpy(void *dest, void *src, size_t n);

int
memcmp(const void *ptr1, const void *ptr2, size_t n);

size_t
strlen(const char *str);
