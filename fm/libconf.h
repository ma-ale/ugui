#ifndef LIBCONF_H_
#define LIBCONF_H_

const char *lcnf_get_conf_file(const char *id, const char *name, int global);
const char *lcnf_get_conf_dir(const char *id, int global);

#endif
