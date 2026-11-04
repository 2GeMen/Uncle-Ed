#include <stdint.h>
int emu_start(const char *core,const char *rom,const char *data);
void emu_stop(void);
void emu_run(void);
void emu_button(int id,int down);
void emu_touch(int x,int y,int down);
const uint32_t *emu_pixels(void);
int emu_width(void);
int emu_height(void);
int emu_save(void);
const char *emu_error(void);
unsigned long emu_frames(void);
unsigned long emu_audio_samples(void);
uint64_t emu_sram_hash(void);

double emu_fps(void);

void emu_volume(float value);

void emu_axis(int stick,int axis,int value);
const char *emu_backend(void);

const char *emu_core_option(const char *key);

unsigned long emu_video_serial(void);
double emu_readback_seconds(void);

unsigned long emu_audio_underruns(void);
unsigned emu_audio_buffered(void);

int emu_state_save(int slot);
int emu_state_load(int slot);
int emu_state_exists(int slot);
const char* emu_state_error(void);

uint64_t emu_vram_hash(void);
