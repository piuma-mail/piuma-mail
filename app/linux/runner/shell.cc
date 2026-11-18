#include "shell.h"

#include <dlfcn.h>
#include <gio/gdesktopappinfo.h>
#include <glib/gstdio.h>

#include <cstring>

namespace {

// AppIndicator's API, from whichever library the system has: no build
// dependency, and a desktop without a tray simply has none.
typedef gpointer (*IndicatorNew)(const gchar* id, const gchar* icon,
                                 int category, const gchar* icon_path);
typedef void (*IndicatorSetStatus)(gpointer indicator, int status);
typedef void (*IndicatorSetMenu)(gpointer indicator, GtkMenu* menu);
typedef void (*IndicatorSetTitle)(gpointer indicator, const gchar* title);

struct IndicatorApi {
  IndicatorNew make = nullptr;
  IndicatorSetStatus status = nullptr;
  IndicatorSetMenu menu = nullptr;
  IndicatorSetTitle title = nullptr;
};

// APP_INDICATOR_CATEGORY_COMMUNICATIONS, APP_INDICATOR_STATUS_*.
constexpr int kCommunications = 1;
constexpr int kPassive = 0;
constexpr int kActive = 1;

const IndicatorApi* Indicators() {
  static IndicatorApi api;
  static bool tried = false;
  if (!tried) {
    tried = true;
    static const char* const kLibraries[] = {"libayatana-appindicator3.so.1",
                                             "libappindicator3.so.1"};
    for (const char* name : kLibraries) {
      void* lib = dlopen(name, RTLD_NOW | RTLD_LOCAL);
      if (lib == nullptr) continue;
      api.make = reinterpret_cast<IndicatorNew>(
          dlsym(lib, "app_indicator_new_with_path"));
      api.status = reinterpret_cast<IndicatorSetStatus>(
          dlsym(lib, "app_indicator_set_status"));
      api.menu = reinterpret_cast<IndicatorSetMenu>(
          dlsym(lib, "app_indicator_set_menu"));
      api.title = reinterpret_cast<IndicatorSetTitle>(
          dlsym(lib, "app_indicator_set_title"));
      if (api.make && api.status && api.menu && api.title) break;
      api = IndicatorApi();
      dlclose(lib);
    }
  }
  return api.make != nullptr ? &api : nullptr;
}

const char kDesktopId[] = APPLICATION_ID ".desktop";

}  // namespace

struct _Shell {
  GApplication* application;
  GtkWindow* window;
  FlMethodChannel* channel;
  // Dart listens: until then later launches wait here.
  gboolean ready;
  GPtrArray* waiting;
  gboolean keep_running;
  gboolean quitting;
  gpointer indicator;
  GtkWidget* menu;
  GtkWidget* open_item;
  GtkWidget* compose_item;
  GtkWidget* quit_item;
};

static void send_open(Shell* self, FlValue* args) {
  fl_method_channel_invoke_method(self->channel, "open", args, nullptr,
                                  nullptr, nullptr);
}

void shell_present(Shell* self) { gtk_window_present(self->window); }

static void quit(Shell* self) {
  self->quitting = TRUE;
  if (self->indicator != nullptr) {
    Indicators()->status(self->indicator, kPassive);
  }
  g_application_quit(self->application);
}

static void on_open(GtkMenuItem*, gpointer data) {
  shell_present(static_cast<Shell*>(data));
}

static void on_compose(GtkMenuItem*, gpointer data) {
  Shell* self = static_cast<Shell*>(data);
  shell_present(self);
  fl_method_channel_invoke_method(self->channel, "compose", nullptr, nullptr,
                                  nullptr, nullptr);
}

static void on_quit(GtkMenuItem*, gpointer data) {
  quit(static_cast<Shell*>(data));
}

// Closing the window while Piuma keeps running only hides it: it goes on
// syncing and notifying; the tray brings it back, or quits it. Without a
// tray (a desktop that shows none) closing quits as before, so Piuma is
// never left running out of reach.
static gboolean on_delete(GtkWidget* widget, GdkEvent*, gpointer data) {
  Shell* self = static_cast<Shell*>(data);
  if (self->keep_running && self->indicator != nullptr && !self->quitting) {
    gtk_widget_hide(widget);
    return TRUE;
  }
  return FALSE;
}

// The folder with the tray's icon, next to the program in the bundle.
static gchar* icon_folder() {
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe == nullptr) return nullptr;
  g_autofree gchar* dir = g_path_get_dirname(exe);
  return g_build_filename(dir, "data", "icons", nullptr);
}

static void set_tray(Shell* self, gboolean on) {
  const IndicatorApi* api = Indicators();
  if (api == nullptr) return;
  if (on && self->indicator == nullptr) {
    g_autofree gchar* icons = icon_folder();
    self->indicator = api->make(APPLICATION_ID, "piuma-mail-tray",
                                kCommunications, icons);
    if (self->indicator == nullptr) return;
    api->menu(self->indicator, GTK_MENU(self->menu));
    api->title(self->indicator, "Piuma Mail");
  }
  if (self->indicator != nullptr) {
    api->status(self->indicator, on ? kActive : kPassive);
  }
}

static const gchar* lookup_string(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return nullptr;
  }
  FlValue* v = fl_value_lookup_string(args, key);
  if (v == nullptr || fl_value_get_type(v) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  const gchar* s = fl_value_get_string(v);
  return s != nullptr && *s != '\0' && strlen(s) < 4096 ? s : nullptr;
}

static gboolean lookup_bool(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return FALSE;
  }
  FlValue* v = fl_value_lookup_string(args, key);
  return v != nullptr && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL &&
         fl_value_get_bool(v);
}

static gint64 lookup_int(FlValue* args, const char* key) {
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    return 0;
  }
  FlValue* v = fl_value_lookup_string(args, key);
  return v != nullptr && fl_value_get_type(v) == FL_VALUE_TYPE_INT
             ? fl_value_get_int(v)
             : 0;
}

// Who opens mailto: links: "piuma", "other", "none", or "unavailable"
// when this build's .desktop file isn't installed (a build from source).
static const gchar* default_mail() {
  g_autoptr(GDesktopAppInfo) ours = g_desktop_app_info_new(kDesktopId);
  if (ours == nullptr) return "unavailable";
  g_autoptr(GAppInfo) current = g_app_info_get_default_for_uri_scheme("mailto");
  if (current == nullptr) return "none";
  return g_strcmp0(g_app_info_get_id(current), kDesktopId) == 0 ? "piuma"
                                                                 : "other";
}

static const gchar* make_default() {
  g_autoptr(GDesktopAppInfo) ours = g_desktop_app_info_new(kDesktopId);
  if (ours == nullptr) return "unavailable";
  g_autoptr(GError) error = nullptr;
  if (!g_app_info_set_as_default_for_type(G_APP_INFO(ours),
                                          "x-scheme-handler/mailto", &error)) {
    g_warning("default mail app: %s", error->message);
  }
  return default_mail();
}

// Starts Piuma at sign-in, without its window: a file in the autostart
// folder (XDG), naming the AppImage when it runs from one.
static void start_at_login(gboolean on) {
  g_autofree gchar* dir =
      g_build_filename(g_get_user_config_dir(), "autostart", nullptr);
  g_autofree gchar* file = g_build_filename(dir, kDesktopId, nullptr);
  if (!on) {
    g_unlink(file);
    return;
  }
  const gchar* image = g_getenv("APPIMAGE");
  g_autofree gchar* exe =
      image != nullptr && g_path_is_absolute(image) &&
              g_file_test(image, G_FILE_TEST_IS_REGULAR)
          ? g_strdup(image)
          : g_file_read_link("/proc/self/exe", nullptr);
  // Exec quoting has its own rules; a path that would need them is not
  // written at all rather than written wrong.
  if (exe == nullptr || strpbrk(exe, "\"`$\\%\n\r") != nullptr) {
    g_warning("start at sign-in: unusual program path, not set");
    return;
  }
  g_autofree gchar* entry = g_strdup_printf(
      "[Desktop Entry]\n"
      "Type=Application\n"
      "Name=Piuma Mail\n"
      "Exec=\"%s\" --background\n"
      "Icon=piuma-mail\n"
      "NoDisplay=true\n"
      "X-GNOME-Autostart-enabled=true\n",
      exe);
  g_mkdir_with_parents(dir, 0700);
  g_autoptr(GError) error = nullptr;
  if (!g_file_set_contents(file, entry, -1, &error)) {
    g_warning("start at sign-in: %s", error->message);
  }
}

// The unread count on the app's launcher icon, for docks that read the
// Unity LauncherEntry signal.
static void launcher_count(Shell* self, gint64 count) {
  GDBusConnection* bus = g_application_get_dbus_connection(self->application);
  if (bus == nullptr) return;
  g_autofree gchar* path = g_strdup_printf(
      "/com/canonical/unity/launcherentry/%u", g_str_hash(APPLICATION_ID));
  GVariantBuilder props;
  g_variant_builder_init(&props, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&props, "{sv}", "count",
                        g_variant_new_int64(count > 0 ? count : 0));
  g_variant_builder_add(&props, "{sv}", "count-visible",
                        g_variant_new_boolean(count > 0));
  g_dbus_connection_emit_signal(
      bus, nullptr, path, "com.canonical.Unity.LauncherEntry", "Update",
      g_variant_new("(sa{sv})", "application://" APPLICATION_ID ".desktop",
                    &props),
      nullptr);
}

static void on_method_call(FlMethodChannel* channel, FlMethodCall* call,
                           gpointer data) {
  Shell* self = static_cast<Shell*>(data);
  const gchar* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  g_autoptr(FlValue) result = nullptr;
  if (g_strcmp0(method, "ready") == 0) {
    self->ready = TRUE;
    for (guint i = 0; i < self->waiting->len; i++) {
      send_open(self, static_cast<FlValue*>(g_ptr_array_index(self->waiting, i)));
    }
    g_ptr_array_set_size(self->waiting, 0);
  } else if (g_strcmp0(method, "keepRunning") == 0) {
    self->keep_running = lookup_bool(args, "on");
    if (const gchar* s = lookup_string(args, "open")) {
      gtk_menu_item_set_label(GTK_MENU_ITEM(self->open_item), s);
    }
    if (const gchar* s = lookup_string(args, "compose")) {
      gtk_menu_item_set_label(GTK_MENU_ITEM(self->compose_item), s);
    }
    if (const gchar* s = lookup_string(args, "quit")) {
      gtk_menu_item_set_label(GTK_MENU_ITEM(self->quit_item), s);
    }
    set_tray(self, self->keep_running);
    // Started hidden at sign-in, but not to stay out of sight (or with
    // no tray to come back from).
    if ((!self->keep_running || self->indicator == nullptr) &&
        !gtk_widget_get_visible(GTK_WIDGET(self->window))) {
      shell_present(self);
    }
  } else if (g_strcmp0(method, "startAtLogin") == 0) {
    start_at_login(lookup_bool(args, "on"));
  } else if (g_strcmp0(method, "unread") == 0) {
    launcher_count(self, lookup_int(args, "count"));
    if (self->indicator != nullptr) {
      if (const gchar* s = lookup_string(args, "tooltip")) {
        Indicators()->title(self->indicator, s);
      }
    }
  } else if (g_strcmp0(method, "defaultMail") == 0) {
    result = fl_value_new_string(default_mail());
  } else if (g_strcmp0(method, "makeDefault") == 0) {
    result = fl_value_new_string(make_default());
  } else if (g_strcmp0(method, "quit") == 0) {
    fl_method_call_respond_success(call, nullptr, nullptr);
    quit(self);
    return;
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  fl_method_call_respond_success(call, result, nullptr);
}

Shell* shell_new(GApplication* application, GtkWindow* window, FlView* view) {
  Shell* self = g_new0(Shell, 1);
  self->application = application;
  self->window = window;
  self->waiting = g_ptr_array_new_with_free_func(
      reinterpret_cast<GDestroyNotify>(fl_value_unref));
  self->menu = gtk_menu_new();
  g_object_ref_sink(self->menu);
  self->open_item = gtk_menu_item_new_with_label("Open Piuma Mail");
  self->compose_item = gtk_menu_item_new_with_label("Compose");
  self->quit_item = gtk_menu_item_new_with_label("Quit");
  g_signal_connect(self->open_item, "activate", G_CALLBACK(on_open), self);
  g_signal_connect(self->compose_item, "activate", G_CALLBACK(on_compose),
                   self);
  g_signal_connect(self->quit_item, "activate", G_CALLBACK(on_quit), self);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->menu), self->open_item);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->menu), self->compose_item);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->menu),
                        gtk_separator_menu_item_new());
  gtk_menu_shell_append(GTK_MENU_SHELL(self->menu), self->quit_item);
  gtk_widget_show_all(self->menu);

  g_signal_connect(window, "delete-event", G_CALLBACK(on_delete), self);

  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(FL_PLUGIN_REGISTRY(view),
                                                  "PiumaShell");
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "piuma/shell",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, on_method_call,
                                            self, nullptr);
  return self;
}

void shell_forward(Shell* self, gchar** arguments) {
  if (arguments == nullptr || arguments[0] == nullptr) return;
  FlValue* list = fl_value_new_list();
  for (int i = 0; arguments[i] != nullptr && i < 64; i++) {
    // Untrusted: Dart checks every word (lib/outside/arrivals.dart).
    if (strlen(arguments[i]) > 512 * 1024 ||
        !g_utf8_validate(arguments[i], -1, nullptr)) {
      continue;
    }
    fl_value_append_take(list, fl_value_new_string(arguments[i]));
  }
  if (!self->ready) {
    if (self->waiting->len < 16) {
      g_ptr_array_add(self->waiting, list);
    } else {
      fl_value_unref(list);
    }
    return;
  }
  send_open(self, list);
  fl_value_unref(list);
}
