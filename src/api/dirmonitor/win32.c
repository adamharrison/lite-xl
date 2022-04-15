#include <SDL.h>
#include <stdbool.h>
#include <windows.h>

enum EState {
  MONITOR_STATE_WAITING,
  MONITOR_STATE_DATA_AVAIALBLE,
  MONITOR_STATE_EXITING
};

struct dirmonitor {
  HANDLE handle;
  char buffer[64512];
  OVERLAPPED overlapped;
  SDL_Thread* thread;
  SDL_mutex* mutex;
  volatile enum EState state;
};


static unsigned int DIR_EVENT_TYPE = 0;
static int dirmonitor_check_thread(void* data) {
  struct dirmonitor* monitor = data;
  while (monitor->state != MONITOR_STATE_EXITING) {
    if (monitor->handle && monitor->state == MONITOR_STATE_WAITING && ReadDirectoryChangesW(monitor->handle, monitor->buffer, sizeof(monitor->buffer), TRUE,  FILE_NOTIFY_CHANGE_FILE_NAME | FILE_NOTIFY_CHANGE_DIR_NAME, NULL, &monitor->overlapped, NULL) != 0) {
      DWORD bytes_transferred;
      GetOverlappedResult(monitor->handle, &monitor->overlapped, &bytes_transferred, TRUE);
      SDL_LockMutex(monitor->mutex);
      if (monitor->state == MONITOR_STATE_WAITING)
        monitor->state = MONITOR_STATE_DATA_AVAIALBLE;
      SDL_UnlockMutex(monitor->mutex);
    } else
      SDL_Delay(1);
    SDL_Event event = { .type = DIR_EVENT_TYPE };
    SDL_PushEvent(&event);
  }
  return 0;
}

struct dirmonitor* init_dirmonitor_win32() {
  if (DIR_EVENT_TYPE == 0)
    DIR_EVENT_TYPE = SDL_RegisterEvents(1);
  struct dirmonitor* monitor = calloc(sizeof(struct dirmonitor), 1);
  monitor->mutex = SDL_CreateMutex();
  return monitor;
}


static void close_monitor_handle(struct dirmonitor* monitor) {
  if (monitor->handle) {
    monitor->state = MONITOR_STATE_EXITING;
    BOOL result = CancelIoEx(monitor->handle, &monitor->overlapped);
    DWORD error = GetLastError();
    if (result == TRUE || error != ERROR_NOT_FOUND) {
      DWORD bytes_transferred;
      GetOverlappedResult( monitor->handle, &monitor->overlapped, &bytes_transferred, TRUE );
    }
    CloseHandle(monitor->handle);
    SDL_WaitThread(monitor->thread, NULL);
    monitor->state = MONITOR_STATE_WAITING;
  }
  monitor->handle = NULL;
}


void deinit_dirmonitor_win32(struct dirmonitor* monitor) {
  close_monitor_handle(monitor);
  SDL_DestroyMutex(monitor->mutex);
  free(monitor);
}


int check_dirmonitor_win32(struct dirmonitor* monitor, int (*change_callback)(int, const char*, void*), void* data) {
  if (monitor->state == MONITOR_STATE_DATA_AVAIALBLE) {
    for (FILE_NOTIFY_INFORMATION* info = (FILE_NOTIFY_INFORMATION*)monitor->buffer; (char*)info < monitor->buffer + sizeof(monitor->buffer); info = (FILE_NOTIFY_INFORMATION*)(((char*)info) + info->NextEntryOffset)) {
      change_callback(info->FileNameLength / sizeof(WCHAR), (char*)info->FileName, data);
      if (!info->NextEntryOffset)
        break;
    }
    monitor->state = MONITOR_STATE_WAITING;
  }
  return 0;
}


int add_dirmonitor_win32(struct dirmonitor* monitor, const char* path) {
  close_monitor_handle(monitor);
  monitor->handle = CreateFileA(path, FILE_LIST_DIRECTORY, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS | FILE_FLAG_OVERLAPPED, NULL);
  if (!monitor->handle || monitor->handle == INVALID_HANDLE_VALUE) 
    return -1;
  monitor->thread = SDL_CreateThread(dirmonitor_check_thread, "dirmonitor_check_thread", monitor);
  return 1;
}


void remove_dirmonitor_win32(struct dirmonitor* monitor, int fd) {
  close_monitor_handle(monitor);
}
