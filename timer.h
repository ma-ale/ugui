#ifndef UG_TIMER_H_
#define UG_TIMER_H_

#include <stdlib.h>

#define TIMER_MAX_PARTIAL 10

int timer_start(void);
int timer_stop(void);
int timer_reset(void);
int timer_partial(int idx);

size_t timer_get_us(int idx);
double timer_get_sec(int idx);

#endif
