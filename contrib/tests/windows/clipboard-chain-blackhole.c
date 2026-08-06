#define WIN32_LEAN_AND_MEAN
#include <windows.h>

static HWND next_viewer;

static LRESULT CALLBACK window_proc(HWND window, UINT message,
                                    WPARAM wparam, LPARAM lparam)
{
  switch (message) {
  case WM_CREATE:
    next_viewer = SetClipboardViewer(window);
    SetTimer(window, 1, 12000, NULL);
    return 0;

  case WM_DRAWCLIPBOARD:
    /* Deliberately do not forward this message. */
    return 0;

  case WM_CHANGECBCHAIN:
    if ((HWND)wparam == next_viewer)
      next_viewer = (HWND)lparam;
    return 0;

  case WM_TIMER:
    DestroyWindow(window);
    return 0;

  case WM_DESTROY:
    ChangeClipboardChain(window, next_viewer);
    PostQuitMessage(0);
    return 0;
  }

  return DefWindowProc(window, message, wparam, lparam);
}

int WINAPI WinMain(HINSTANCE instance, HINSTANCE previous,
                   LPSTR command_line, int show_command)
{
  const char *class_name = "TigerVNCClipboardChainBlackhole";
  WNDCLASSA window_class = {0};
  HWND window;
  MSG message;

  (void)previous;
  (void)command_line;
  (void)show_command;

  window_class.lpfnWndProc = window_proc;
  window_class.hInstance = instance;
  window_class.lpszClassName = class_name;
  if (!RegisterClassA(&window_class))
    return 1;

  window = CreateWindowA(class_name, class_name, 0,
                         0, 0, 0, 0, NULL, NULL, instance, NULL);
  if (!window)
    return 2;

  while (GetMessage(&message, NULL, 0, 0) > 0) {
    TranslateMessage(&message);
    DispatchMessage(&message);
  }

  return 0;
}
