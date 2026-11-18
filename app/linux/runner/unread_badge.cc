#include "unread_badge.h"

static const char kBadgeKey[] = "piuma-unread-badge";

static void on_method_call(FlMethodChannel* channel, FlMethodCall* call,
                           gpointer user_data) {
  FlView* view = FL_VIEW(user_data);
  if (g_strcmp0(fl_method_call_get_name(call), "set") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  FlValue* args = fl_method_call_get_args(call);
  FlValue* title = args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
                       ? fl_value_lookup_string(args, "title")
                       : nullptr;
  GtkWidget* top = gtk_widget_get_toplevel(GTK_WIDGET(view));
  if (title != nullptr && fl_value_get_type(title) == FL_VALUE_TYPE_STRING &&
      GTK_IS_WINDOW(top)) {
    const gchar* text = fl_value_get_string(title);
    GtkWindow* window = GTK_WINDOW(top);
    gtk_window_set_title(window, text);
    // Under GNOME the title sits in the header bar.
    GtkWidget* bar = gtk_window_get_titlebar(window);
    if (bar != nullptr && GTK_IS_HEADER_BAR(bar)) {
      gtk_header_bar_set_title(GTK_HEADER_BAR(bar), text);
    }
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}

void unread_badge_register(FlPluginRegistrar* registrar) {
  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (view == nullptr) return;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "piuma/badge",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, on_method_call, view,
                                            nullptr);
  // Kept as long as the view.
  g_object_set_data_full(G_OBJECT(view), kBadgeKey, channel, g_object_unref);
}
