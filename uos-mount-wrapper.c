#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <string.h>

static int (*real_mount)(const char *source, const char *target,
                         const char *filesystemtype, unsigned long mountflags,
                         const void *data) = NULL;

static int (*real_umount2)(const char *target, int flags) = NULL;

static int is_api_fs_path(const char *target) {
    if (!target) return 0;
    if (strcmp(target, "/run") == 0) return 1;
    if (strcmp(target, "/run/lock") == 0) return 1;
    if (strcmp(target, "/dev/shm") == 0) return 1;
    return 0;
}

int mount(const char *source, const char *target,
          const char *filesystemtype, unsigned long mountflags,
          const void *data) {
    if (!real_mount)
        real_mount = (int (*)(const char *, const char *, const char *, unsigned long, const void *))dlsym(RTLD_NEXT, "mount");

    int ret = real_mount(source, target, filesystemtype, mountflags, data);
    if (ret != 0 && errno == EPERM && is_api_fs_path(target)) {
        return 0;
    }
    return ret;
}

int umount2(const char *target, int flags) {
    if (!real_umount2)
        real_umount2 = (int (*)(const char *, int))dlsym(RTLD_NEXT, "umount2");

    int ret = real_umount2(target, flags);
    if (ret != 0 && errno == EPERM && is_api_fs_path(target)) {
        return 0;
    }
    return ret;
}
