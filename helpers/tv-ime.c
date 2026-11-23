// tv-ime: the Omarchy TV input method.
//
// Registers as the session's input method (zwp_input_method_v2), so the
// compositor tells it whenever a text field gains or loses focus in any app
// that speaks text-input (GTK, Qt, Chromium with --enable-wayland-ime). The TV
// shell runs it and talks to it over stdio:
//
//   stdout  "active <purpose> <hint>"   a text field is focused
//           "inactive"                  it lost focus
//           "committed" | "failed"      reply to a commit
//           "unavailable"               another input method holds the seat
//   stdin   "commit <text>"             type text into the field (\n, \\ escaped)
//           "delete <before> <after>"   delete around the cursor (bytes)
//
// Purpose values follow text-input-v3: 8 = password, 4/5 = digits/number,
// 6 = phone, 7 = url, 9 = email, ...

#define _GNU_SOURCE
#include <errno.h>
#include <poll.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wayland-client.h>

#include "input-method-unstable-v2-client.h"

static struct wl_seat *seat;
static struct zwp_input_method_manager_v2 *manager;
static struct zwp_input_method_v2 *im;
static uint32_t serial;
static bool pending_active, active, reported;
static uint32_t pending_purpose, pending_hint;

static void say(const char *line) {
  fputs(line, stdout);
  fputc('\n', stdout);
  fflush(stdout);
}

static void on_activate(void *d, struct zwp_input_method_v2 *m) {
  (void)d; (void)m;
  pending_active = true;
  pending_purpose = pending_hint = 0;
}
static void on_deactivate(void *d, struct zwp_input_method_v2 *m) {
  (void)d; (void)m;
  pending_active = false;
}
static void on_surrounding(void *d, struct zwp_input_method_v2 *m, const char *t, uint32_t c, uint32_t a) {
  (void)d; (void)m; (void)t; (void)c; (void)a;
}
static void on_cause(void *d, struct zwp_input_method_v2 *m, uint32_t cause) {
  (void)d; (void)m; (void)cause;
}
static void on_content_type(void *d, struct zwp_input_method_v2 *m, uint32_t hint, uint32_t purpose) {
  (void)d; (void)m;
  pending_hint = hint;
  pending_purpose = purpose;
}
static void on_done(void *d, struct zwp_input_method_v2 *m) {
  (void)d; (void)m;
  serial++;
  if (pending_active != active || !reported || pending_active) {
    char line[64];
    if (pending_active)
      snprintf(line, sizeof line, "active %u %u", pending_purpose, pending_hint);
    else
      snprintf(line, sizeof line, "inactive");
    // Only report changes (and purpose updates while active).
    static char last[64];
    if (strcmp(line, last) != 0) {
      say(line);
      strcpy(last, line);
    }
    reported = true;
  }
  active = pending_active;
}
static void on_unavailable(void *d, struct zwp_input_method_v2 *m) {
  (void)d; (void)m;
  say("unavailable");
}

static const struct zwp_input_method_v2_listener im_listener = {
  .activate = on_activate,
  .deactivate = on_deactivate,
  .surrounding_text = on_surrounding,
  .text_change_cause = on_cause,
  .content_type = on_content_type,
  .done = on_done,
  .unavailable = on_unavailable,
};

static void on_global(void *d, struct wl_registry *r, uint32_t name, const char *iface, uint32_t version) {
  (void)d; (void)version;
  if (strcmp(iface, wl_seat_interface.name) == 0 && !seat)
    seat = wl_registry_bind(r, name, &wl_seat_interface, 1);
  else if (strcmp(iface, zwp_input_method_manager_v2_interface.name) == 0)
    manager = wl_registry_bind(r, name, &zwp_input_method_manager_v2_interface, 1);
}
static void on_global_remove(void *d, struct wl_registry *r, uint32_t name) {
  (void)d; (void)r; (void)name;
}
static const struct wl_registry_listener registry_listener = { on_global, on_global_remove };

static void unescape(char *s) {
  char *o = s;
  for (char *i = s; *i; i++) {
    if (*i == '\\' && i[1] == 'n') { *o++ = '\n'; i++; }
    else if (*i == '\\' && i[1] == '\\') { *o++ = '\\'; i++; }
    else *o++ = *i;
  }
  *o = 0;
}

static void handle(char *line, struct wl_display *display) {
  size_t n = strlen(line);
  if (n && line[n - 1] == '\n') line[--n] = 0;
  if (strncmp(line, "commit ", 7) == 0) {
    if (!active) { say("failed"); return; }
    unescape(line + 7);
    zwp_input_method_v2_commit_string(im, line + 7);
    zwp_input_method_v2_commit(im, serial);
    wl_display_flush(display);
    say("committed");
  } else if (strncmp(line, "delete ", 7) == 0) {
    unsigned before = 0, after = 0;
    if (!active || sscanf(line + 7, "%u %u", &before, &after) < 1) { say("failed"); return; }
    zwp_input_method_v2_delete_surrounding_text(im, before, after);
    zwp_input_method_v2_commit(im, serial);
    wl_display_flush(display);
    say("committed");
  }
}

int main(void) {
  struct wl_display *display = wl_display_connect(NULL);
  if (!display) { fprintf(stderr, "tv-ime: no Wayland display\n"); return 1; }
  struct wl_registry *registry = wl_display_get_registry(display);
  wl_registry_add_listener(registry, &registry_listener, NULL);
  wl_display_roundtrip(display);
  if (!seat || !manager) { fprintf(stderr, "tv-ime: compositor has no input-method-v2\n"); say("unsupported"); return 2; }

  im = zwp_input_method_manager_v2_get_input_method(manager, seat);
  zwp_input_method_v2_add_listener(im, &im_listener, NULL);
  wl_display_roundtrip(display);
  say("ready");

  char *buf = NULL;
  size_t cap = 0;
  struct pollfd fds[2] = {
    { .fd = wl_display_get_fd(display), .events = POLLIN },
    { .fd = STDIN_FILENO, .events = POLLIN },
  };
  for (;;) {
    while (wl_display_prepare_read(display) != 0) wl_display_dispatch_pending(display);
    wl_display_flush(display);
    if (poll(fds, 2, -1) < 0) {
      wl_display_cancel_read(display);
      if (errno == EINTR) continue;
      break;
    }
    if (fds[0].revents & POLLIN) {
      if (wl_display_read_events(display) < 0) break;
      wl_display_dispatch_pending(display);
    } else {
      wl_display_cancel_read(display);
    }
    if (fds[0].revents & (POLLHUP | POLLERR)) break;
    if (fds[1].revents & (POLLIN | POLLHUP)) {
      if (getline(&buf, &cap, stdin) < 0) break; // the shell went away
      handle(buf, display);
    }
  }
  free(buf);
  return 0;
}
