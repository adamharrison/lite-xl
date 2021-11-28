#include <stdlib.h>
#ifdef _WIN32
  #include <windows.h>
  #define PATH_MAX MAX_PATH
#elif __APPLE__
  #include <sys/event.h>
#elif __linux__
  #include <sys/inotify.h>
#endif
#include <unistd.h>
#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <string.h>
#include "dirmonitor.h"

struct dirmonitor {
  int fd;
  #if _WIN32
    HANDLE handles[8192];
  #endif
};

struct dirmonitor* init_dirmonitor() {
  struct dirmonitor* monitor = calloc(sizeof(struct dirmonitor), 1);
  #if __APPLE__
    monitor->fd = kqueue();
  #elif __linux__
    monitor->fd = inotify_init1(IN_NONBLOCK);
  #endif
  return monitor;
}
void deinit_dirmonitor(struct dirmonitor* monitor) {
  #if _WIN32
    for (int i = 0; i < monitor->fd; ++i)
      FindCloseChangeNotification(monitor[i]);
  #else
    close(monitor->fd);
  #endif
  free(monitor);
}

int check_dirmonitor(struct dirmonitor* monitor, int (*change_callback)(int, void*), void* data) {
  #if _WIN32
    while (1) {
      DWORD dwWaitStatus = WaitForMultipleObjects(monitor->fd, monitor->handles, FALSE, 0); 
      if (dwWaitStatus == WAIT_TIMEOUT)
        return 0;
      if dwWaitStatus < WAIT_OBJECT_0)
        return -1;
      unsigned int idx = dwWaitStatus - WAIT_OBJECT_0;
      if (!FindNextChangeNotification(monitor->handles[idx]))
        change_callback(idx);
    }
  #elif __APPLE__
    struct kevent change, event;
    while (1) {
      struct timespec tm = {0};
      int nev = kevent(monitor->fd, NULL, 0, &event, 1, &tm);
      if (nev <= 0)
        return nev;
      chnage_callback(event->ident);
    }
  #elif __linux__
    char buf[4096] __attribute__ ((aligned(__alignof__(struct inotify_event))));
    while (1) {
      ssize_t len = read(monitor->fd, buf, sizeof(buf));
      if (len == -1 && errno != EAGAIN)
        return errno;
      if (len <= 0)
        return 0;
      for (char *ptr = buf; ptr < buf + len; ptr += sizeof(struct inotify_event) + ((struct inotify_event*)ptr)->len)
        change_callback(((const struct inotify_event *) ptr)->wd, data);
    }
  #endif
}

int add_dirmonitor(struct dirmonitor* monitor, const char* path) {
  #if _WIN32
    monitor->handles[monitor->fd++] = FindFirstChangeNotification(path, FALSE, FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME);
    return monitor->fd - 1;
  #elif __APPLE__
    int fd = open(path, O_RDONLY);
    struct kevent change, event;
    EV_SET(&change, fd, EVFILT_VNODE, EV_ADD | EV_ENABLE, NOTE_DELETE | NOTE_EXTEND | NOTE_WRITE | NOTE_ATTRIB, 0, 0);
    kevent(monitor->fd, &change, 1, NULL, 0, NULL);
    return fd;
  #elif __linux__
    return inotify_add_watch(monitor->fd, path, IN_CREATE | IN_DELETE | IN_MOVED_FROM | IN_MOVED_TO);
  #endif
}
