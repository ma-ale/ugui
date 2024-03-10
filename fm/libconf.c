#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <stdarg.h>

#include <linux/limits.h>
#include <sys/stat.h>
#include <sys/types.h>

#define PATHS_NO 3

static char temp[PATH_MAX]            = {0};
static int  valid_paths               = 0;
static char paths[PATHS_NO][PATH_MAX] = {0}; // 0: xdg, 1: fallback, 2: global

static const mode_t CONFDIR_MODE = S_IRWXU | S_IRWXU | S_IRWXU | S_IRWXU;

static void err(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);

	fprintf(stderr, "[libconf]: ");
	vfprintf(stderr, fmt, ap);
	fprintf(stderr, "\n");

	va_end(ap);
}

// implements "mkdir -p"
static int mkdir_p(const char *path)
{
	char tmp_path[PATH_MAX] = {0};
	strncpy(tmp_path, path, PATH_MAX - 1);
	struct stat st;

	for (char *tk = strtok(tmp_path, "/"); tk != NULL; tk = strtok(NULL, "/")) {
		if (tk != tmp_path) {
			tk[-1] = '/';
		}

		if (stat(tmp_path, &st)) {
			if (errno != ENOENT) {
				err("could not stat() %s: %s",
				    tmp_path,
				    strerror(errno));
				return 1;
			}

			if (mkdir(tmp_path, CONFDIR_MODE)) {
				err("could not mkdir() %s: %s",
				    tmp_path,
				    strerror(errno));
				return 1;
			}
		} else if (!S_ISDIR(st.st_mode)) {
			err("could not create directory %s: file exists but it is "
			    "not a directory",
			    tmp_path);
			return 1;
		}
	}
	return 0;
}

// TODO: add a way to add a custom directory to the paths, for example via an
//       environment variable
// TODO: maybe add a LIBCONF_PATH that overrides the defaults
/* default paths are:
 * 1. ${XDG_CONFIG_HOME}/libconf/appid.d/
 * 2. ${HOME}/.config/libconf/appid.d/
 * 3. etc/libconf/appid.d/
 */
static int fill_paths(const char *id)
{
	// TODO: verify id
	if (id == NULL) {
		err("must provide a valid app id");
		return 1;
	}

	const char *xdg = getenv("XDG_CONFIG_HOME");
	if (xdg != NULL) {
		snprintf(paths[0], PATH_MAX, "%s/libconf/%s.d", xdg, id);
	}

	const char *home = getenv("HOME");
	if (home) {
		snprintf(temp, PATH_MAX, "%s/.config/libconf/%s.d", home, id);

		if (mkdir_p(temp) == 0) {
			strcpy(paths[1], temp);
		}
	}

	// do not create global config path since most likely we don't have
	// the necessary permissions to do so
	snprintf(paths[2], PATH_MAX, "/etc/libconf/%s.d", id);

	for (size_t i = 0; i < PATHS_NO; i++) {
		printf("paths[%ld] = %s\n", i, paths[i]);
	}

	valid_paths = 1;

	return 0;
}

// get config file path
const char *lcnf_get_conf_file(const char *id, const char *name, int global)
{
	static char str[PATH_MAX] = {0};

	if (id == NULL) {
		return NULL;
	}

	if (!valid_paths) {
		if (fill_paths(id)) {
			return NULL;
		}
	}

	// quick path for global config file
	if (global && paths[2][0] != '\0') {
		snprintf(str, PATH_MAX, "%s/%s", paths[2], name);
		return str;
	}

	int found = 0;
	for (size_t i = 0; i < PATHS_NO; i++) {
		if (paths[i][0] == '\0') {
			continue;
		}

		struct stat st;
		snprintf(str, PATH_MAX, "%s/%s", paths[i], name);

		if (stat(str, &st) && errno != ENOENT) {
			err("could not stat %s: %s", str, strerror(errno));
		}

		if (S_ISREG(st.st_mode)) {
			found = 1;
			break;
		}
	}

	return found ? str : NULL;
}

// get config file directory path
const char *lcnf_get_conf_dir(const char *id, int global)
{
	if (id == NULL) {
		return NULL;
	}

	if (global) {
		return paths[2][0] != '\0' ? paths[2] : NULL;
	}

	if (paths[0][0] != '\0') {
		return paths[0];
	} else if (paths[1][0] != '\0') {
		return paths[1];
	} else {
		return NULL;
	}
}

// TODO: watch directory for file updates
int lcnf_watch_conf_dir(const char *id, int global);

// TODO: collect all files into a temporary one, useful for when you have multiple
//       configuration files like 00-foo.conf, 01-bar.conf and 99-baz.conf
const char *lcnf_collect_conf_files(const char *id, int global);

#if 1

int main(void)
{
	const char *p = lcnf_get_conf_file("pippo", "pippo.toml", 0);
	if (p) {
		printf("config found: %s\n", p);
	} else {
		printf("config not found\n");
	}
	return 0;
}

#endif
