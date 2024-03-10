#define _POSIX_C_SOURCE 200809l

#include <time.h>

#include "timer.h"

const clockid_t CLOCK_ID = CLOCK_PROCESS_CPUTIME_ID;

struct _timer {
	struct timespec start, stop;
	struct timespec times[TIMER_MAX_PARTIAL];
} timer = {0};

int timer_start(void) { return clock_gettime(CLOCK_ID, &timer.start); }

int timer_reset(void)
{
	timer = (struct _timer) {0};
	return 0;
}

int timer_stop(void) { return clock_gettime(CLOCK_ID, &timer.stop); }

// partial clocks also update the stop time
int timer_partial(int idx)
{
	if (idx > TIMER_MAX_PARTIAL || idx < 0) {
		return -1;
	}
	clock_gettime(CLOCK_ID, &timer.stop);
	return clock_gettime(CLOCK_ID, &(timer.times[idx]));
}

size_t timer_get_us(int idx)
{
	if (idx > TIMER_MAX_PARTIAL) {
		return -1;
	}

	struct timespec ts = {0};
	if (idx < 0) {
		ts = timer.stop;
	} else {
		ts = timer.times[idx];
	}
	ts.tv_sec -= timer.start.tv_sec;
	ts.tv_nsec -= timer.start.tv_nsec;

	// FIXME: check overflow
	return (ts.tv_nsec / 1000) + (ts.tv_sec * 1000000);
}

double timer_get_sec(int idx)
{
	if (idx > TIMER_MAX_PARTIAL) {
		return -1;
	}

	struct timespec ts = {0};
	if (idx < 0) {
		ts = timer.stop;
	} else {
		ts = timer.times[idx];
	}
	ts.tv_sec -= timer.start.tv_sec;
	ts.tv_nsec -= timer.start.tv_nsec;

	return (double)ts.tv_sec + ((double)ts.tv_nsec / 1e9);
}
