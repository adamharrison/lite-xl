#ifndef DIRMONITOR_H
#define DIRMONITOR_H

struct dirmonitor* init_dirmonitor();
void deinit_dirmonitor(struct dirmonitor* monitor);
int check_dirmonitor(struct dirmonitor* monitor, int (*change_callback)(int, void*), void* data);
int add_dirmonitor(struct dirmonitor* monitor, const char* path);

#endif
