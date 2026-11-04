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

double hardware_readback_seconds(void);
double hardware_conversion_seconds(void);

int hardware_resize(unsigned width,unsigned height);

unsigned hardware_target_width(void);
unsigned hardware_target_height(void);
