#include "original_paper.h"

#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

// The papers of one Flutter view, which is one window.
struct Papers {
  FlMethodChannel* channel;
  FlView* view;
  // Paper id from Dart -> Paper*.
  GHashTable* papers;
};

// One original: a clip the size of what shows, holding the web view at
// the paper's full size, so the part scrolled out of the reader is cut.
struct Paper {
  Papers* owner;
  int64_t id;
  GtkWidget* clip;
  GtkWidget* web;
  GdkRectangle shown;
};

static const char kPapersKey[] = "piuma-original-papers";
static const char kPaperKey[] = "piuma-original-paper";
static const char kOverlayKey[] = "piuma-original-overlay";

// Places each clip where Dart said, over the Flutter view.
static gboolean on_child_position(GtkOverlay* overlay, GtkWidget* widget,
                                  GdkRectangle* allocation, gpointer data) {
  Paper* paper =
      static_cast<Paper*>(g_object_get_data(G_OBJECT(widget), kPaperKey));
  if (paper == nullptr) return FALSE;
  *allocation = paper->shown;
  return TRUE;
}

// The overlay the view sits in. The main window starts with one; a window
// made later (a message in its own window) gets it the first time.
static GtkOverlay* overlay_for(FlView* view) {
  GtkWidget* child = GTK_WIDGET(view);
  GtkWidget* parent = gtk_widget_get_parent(child);
  if (parent == nullptr) return nullptr;
  if (!GTK_IS_OVERLAY(parent)) {
    GtkWidget* overlay = gtk_overlay_new();
    g_object_ref(child);
    gtk_container_remove(GTK_CONTAINER(parent), child);
    gtk_container_add(GTK_CONTAINER(overlay), child);
    g_object_unref(child);
    gtk_container_add(GTK_CONTAINER(parent), overlay);
    gtk_widget_show(overlay);
    parent = overlay;
  }
  if (g_object_get_data(G_OBJECT(parent), kOverlayKey) == nullptr) {
    g_object_set_data(G_OBJECT(parent), kOverlayKey, GINT_TO_POINTER(1));
    g_signal_connect(parent, "get-child-position",
                     G_CALLBACK(on_child_position), nullptr);
  }
  return GTK_OVERLAY(parent);
}

static void send_link(Paper* paper, const char* uri) {
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "id", fl_value_new_int(paper->id));
  fl_value_set_string_take(args, "url", fl_value_new_string(uri));
  fl_method_channel_invoke_method(paper->owner->channel, "link", args,
                                  nullptr, nullptr, nullptr);
}

static void on_measured(GObject* object, GAsyncResult* res, gpointer data) {
  GError* error = nullptr;
  JSCValue* value = webkit_web_view_evaluate_javascript_finish(
      WEBKIT_WEB_VIEW(object), res, &error);
  if (value == nullptr) {
    if (error != nullptr) g_error_free(error);
    return;
  }
  double h = jsc_value_is_number(value)
                 ? jsc_value_to_double(value)
                 : 0;
  g_object_unref(value);
  Paper* paper = static_cast<Paper*>(
      g_object_get_data(object, kPaperKey));
  if (paper != nullptr && h > 0) {
    g_autoptr(FlValue) args = fl_value_new_map();
    fl_value_set_string_take(args, "id", fl_value_new_int(paper->id));
    fl_value_set_string_take(args, "height", fl_value_new_float(h));
    fl_method_channel_invoke_method(paper->owner->channel, "height", args,
                                    nullptr, nullptr, nullptr);
  }
}

static void on_load_changed(WebKitWebView* web, WebKitLoadEvent event,
                            gpointer data) {
  if (event != WEBKIT_LOAD_FINISHED) return;
  webkit_web_view_evaluate_javascript(
      web,
      "Math.max(document.body ? document.body.scrollHeight : 0, "
      "document.documentElement ? document.documentElement.scrollHeight : 0)",
      -1, nullptr, nullptr, nullptr, on_measured, nullptr);
}

// Nothing opens in the web view: the email itself loads, links inside it
// (#section) scroll, and every other link the reader clicks goes to the
// app, which cleans it and asks when its text shows another address.
static gboolean on_decide_policy(WebKitWebView* web,
                                 WebKitPolicyDecision* decision,
                                 WebKitPolicyDecisionType type,
                                 gpointer data) {
  if (type == WEBKIT_POLICY_DECISION_TYPE_RESPONSE) return FALSE;
  Paper* paper = static_cast<Paper*>(data);
  WebKitNavigationAction* action =
      webkit_navigation_policy_decision_get_navigation_action(
          WEBKIT_NAVIGATION_POLICY_DECISION(decision));
  const char* uri =
      webkit_uri_request_get_uri(webkit_navigation_action_get_request(action));
  if (type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION &&
      (g_strcmp0(uri, "about:blank") == 0 ||
       g_str_has_prefix(uri, "about:blank#"))) {
    webkit_policy_decision_use(decision);
    return TRUE;
  }
  webkit_policy_decision_ignore(decision);
  if (webkit_navigation_action_get_navigation_type(action) ==
          WEBKIT_NAVIGATION_TYPE_LINK_CLICKED &&
      uri != nullptr && !g_str_has_prefix(uri, "about:")) {
    send_link(paper, uri);
  }
  return TRUE;
}

// The right-click menu keeps only Copy and Select All: no Open Link, no
// Reload, no Inspect.
static gboolean on_context_menu(WebKitWebView* web, WebKitContextMenu* menu,
                                GdkEvent* event, WebKitHitTestResult* hit,
                                gpointer data) {
  GList* items = g_list_copy(webkit_context_menu_get_items(menu));
  for (GList* l = items; l != nullptr; l = l->next) {
    WebKitContextMenuItem* item = WEBKIT_CONTEXT_MENU_ITEM(l->data);
    WebKitContextMenuAction a = webkit_context_menu_item_get_stock_action(item);
    if (a != WEBKIT_CONTEXT_MENU_ACTION_COPY &&
        a != WEBKIT_CONTEXT_MENU_ACTION_SELECT_ALL) {
      webkit_context_menu_remove(menu, item);
    }
  }
  g_list_free(items);
  return webkit_context_menu_get_n_items(menu) == 0;
}

// The email's own policy (`default-src 'none'`) and stripped markup stop
// any script in the message; the host evaluates only its height expression.
static GtkWidget* new_web_view() {
  WebKitSettings* settings = webkit_settings_new();
  webkit_settings_set_enable_javascript(settings, TRUE);
  webkit_settings_set_enable_javascript_markup(settings, FALSE);
  webkit_settings_set_javascript_can_open_windows_automatically(settings,
                                                                FALSE);
  webkit_settings_set_enable_html5_local_storage(settings, FALSE);
  webkit_settings_set_enable_page_cache(settings, FALSE);
  webkit_settings_set_enable_webaudio(settings, FALSE);
  webkit_settings_set_enable_webgl(settings, FALSE);
  webkit_settings_set_enable_media(settings, FALSE);
  webkit_settings_set_enable_developer_extras(settings, FALSE);
  webkit_settings_set_enable_back_forward_navigation_gestures(settings, FALSE);
  // Drawn by the CPU: inside the clip, accelerated drawing left the top of
  // the paper blank, and an email doesn't need the GPU.
  webkit_settings_set_hardware_acceleration_policy(
      settings, WEBKIT_HARDWARE_ACCELERATION_POLICY_NEVER);
  GtkWidget* web = GTK_WIDGET(g_object_new(WEBKIT_TYPE_WEB_VIEW, "settings",
                                           settings, "is-ephemeral", TRUE,
                                           nullptr));
  g_object_unref(settings);
  return web;
}

static void paper_free(gpointer data) {
  Paper* paper = static_cast<Paper*>(data);
  if (paper->clip != nullptr) {
    g_object_remove_weak_pointer(G_OBJECT(paper->clip),
                                 reinterpret_cast<gpointer*>(&paper->clip));
    gtk_widget_destroy(paper->clip);
  }
  g_free(paper);
}

static void papers_free(gpointer data) {
  Papers* papers = static_cast<Papers*>(data);
  g_hash_table_destroy(papers->papers);
  g_object_unref(papers->channel);
  g_free(papers);
}

static double number(FlValue* args, const char* key) {
  FlValue* v = fl_value_lookup_string(args, key);
  if (v == nullptr) return 0;
  if (fl_value_get_type(v) == FL_VALUE_TYPE_FLOAT) return fl_value_get_float(v);
  if (fl_value_get_type(v) == FL_VALUE_TYPE_INT) return fl_value_get_int(v);
  return 0;
}

static const char* text(FlValue* args, const char* key) {
  FlValue* v = fl_value_lookup_string(args, key);
  if (v == nullptr || fl_value_get_type(v) != FL_VALUE_TYPE_STRING) {
    return "";
  }
  return fl_value_get_string(v);
}

static Paper* lookup(Papers* papers, FlValue* args) {
  int64_t id = static_cast<int64_t>(number(args, "id"));
  Paper* paper = static_cast<Paper*>(
      g_hash_table_lookup(papers->papers, GINT_TO_POINTER(id)));
  if (paper != nullptr && paper->clip == nullptr) {
    g_hash_table_remove(papers->papers, GINT_TO_POINTER(id));
    return nullptr;
  }
  return paper;
}

// open {id, html, background}: a new paper, hidden until placed.
static void open_paper(Papers* papers, FlValue* args) {
  GtkOverlay* overlay = overlay_for(papers->view);
  if (overlay == nullptr) return;
  Paper* paper = g_new0(Paper, 1);
  paper->owner = papers;
  paper->id = static_cast<int64_t>(number(args, "id"));
  paper->clip = gtk_layout_new(nullptr, nullptr);
  // The window can go first, and the clip with it.
  g_object_add_weak_pointer(G_OBJECT(paper->clip),
                            reinterpret_cast<gpointer*>(&paper->clip));
  g_object_set_data(G_OBJECT(paper->clip), kPaperKey, paper);
  paper->web = new_web_view();
  g_object_set_data(G_OBJECT(paper->web), kPaperKey, paper);
  guint32 argb = static_cast<guint32>(number(args, "background"));
  GdkRGBA background = {((argb >> 16) & 0xff) / 255.0,
                        ((argb >> 8) & 0xff) / 255.0, (argb & 0xff) / 255.0,
                        1.0};
  webkit_web_view_set_background_color(WEBKIT_WEB_VIEW(paper->web),
                                       &background);
  g_signal_connect(paper->web, "decide-policy", G_CALLBACK(on_decide_policy),
                   paper);
  g_signal_connect(paper->web, "load-changed", G_CALLBACK(on_load_changed),
                   paper);
  g_signal_connect(paper->web, "context-menu", G_CALLBACK(on_context_menu),
                   nullptr);
  gtk_layout_put(GTK_LAYOUT(paper->clip), paper->web, 0, 0);
  gtk_widget_show(paper->web);
  gtk_overlay_add_overlay(overlay, paper->clip);
  webkit_web_view_load_html(WEBKIT_WEB_VIEW(paper->web), text(args, "html"),
                            "about:blank");
  g_hash_table_insert(papers->papers, GINT_TO_POINTER(paper->id), paper);
}

// place {id, visible, x, y, width, height, clipX, clipY, clipWidth,
// clipHeight}: where the paper is in the Flutter view, and the part of it
// that shows.
static void place_paper(Paper* paper, FlValue* args) {
  FlValue* visible = fl_value_lookup_string(args, "visible");
  int cw = static_cast<int>(number(args, "clipWidth"));
  int ch = static_cast<int>(number(args, "clipHeight"));
  if (visible == nullptr || !fl_value_get_bool(visible) || cw <= 0 ||
      ch <= 0) {
    // Keys go back to the app, or a dialog over the paper can't hear Esc.
    if (gtk_widget_has_focus(paper->web)) {
      gtk_widget_grab_focus(GTK_WIDGET(paper->owner->view));
    }
    gtk_widget_hide(paper->clip);
    return;
  }
  int cx = static_cast<int>(number(args, "clipX"));
  int cy = static_cast<int>(number(args, "clipY"));
  int x = static_cast<int>(number(args, "x"));
  int y = static_cast<int>(number(args, "y"));
  int w = static_cast<int>(number(args, "width"));
  int h = static_cast<int>(number(args, "height"));
  paper->shown = {cx, cy, cw, ch};
  gtk_layout_set_size(GTK_LAYOUT(paper->clip), w, h);
  gtk_layout_move(GTK_LAYOUT(paper->clip), paper->web, x - cx, y - cy);
  gtk_widget_set_size_request(paper->web, w, h);
  gtk_widget_show(paper->clip);
  gtk_widget_queue_resize(paper->clip);
}

static void on_method_call(FlMethodChannel* channel, FlMethodCall* call,
                           gpointer data) {
  Papers* papers = static_cast<Papers*>(data);
  const char* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  if (args == nullptr || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
    fl_method_call_respond_error(call, "args", "expected a map", nullptr,
                                 nullptr);
    return;
  }
  if (g_strcmp0(method, "open") == 0) {
    open_paper(papers, args);
  } else if (Paper* paper = lookup(papers, args)) {
    if (g_strcmp0(method, "place") == 0) {
      place_paper(paper, args);
    } else if (g_strcmp0(method, "load") == 0) {
      webkit_web_view_load_html(WEBKIT_WEB_VIEW(paper->web),
                                text(args, "html"), "about:blank");
    } else if (g_strcmp0(method, "close") == 0) {
      g_hash_table_remove(papers->papers, GINT_TO_POINTER(paper->id));
    }
  }
  fl_method_call_respond_success(call, nullptr, nullptr);
}

void original_paper_register(FlPluginRegistrar* registrar) {
  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (view == nullptr) return;
  Papers* papers = g_new0(Papers, 1);
  papers->view = view;
  papers->papers =
      g_hash_table_new_full(g_direct_hash, g_direct_equal, nullptr, paper_free);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  papers->channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "piuma/original",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(papers->channel, on_method_call,
                                            papers, nullptr);
  g_object_set_data_full(G_OBJECT(view), kPapersKey, papers, papers_free);
}
