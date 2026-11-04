#include <stdbool.h>
#include <stdint.h>
bool hardware_environment(unsigned cmd, void *data);
int hardware_start(void);
void hardware_current(void);
int hardware_read(uint32_t *pixels, unsigned width, unsigned height);
void hardware_stop(void);
const char *hardware_error(void);
const char *hardware_backend(void);

void hardware_release_core(void);

void hardware_size(unsigned width,unsigned height);
double hardware_read_seconds(void);
