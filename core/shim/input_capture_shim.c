#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <glib.h>
#include <gio/gio.h>
#include <libportal/portal.h>
#include <libportal/inputcapture.h>

#define TOKEN_FILE_REL "/.local/share/Deskflow/input_capture_restore_token"

typedef struct {
    XdpPortal *portal;
    XdpParent *parent;
    XdpInputCapability capabilities;
    GCancellable *cancellable;
    GAsyncReadyCallback orig_callback;
    gpointer orig_data;
    XdpInputCaptureSession *session;
} ShimContext;

typedef struct {
    int x;
    int y;
    int w;
    int h;
} ShimScreen;

static ShimScreen g_screens[16];
static int g_num_screens = 0;

static char *get_token_file(void) {
    const char *home = g_get_home_dir();
    if (!home) return NULL;
    return g_build_filename(home, TOKEN_FILE_REL, NULL);
}

static char *read_saved_token(void) {
    char *path = get_token_file();
    if (!path) return NULL;
    char *token = NULL;
    if (g_file_get_contents(path, &token, NULL, NULL)) {
        g_strstrip(token);
        if (strlen(token) > 0) {
            g_free(path);
            return token;
        }
        g_free(token);
    }
    g_free(path);
    return NULL;
}

static void save_token(const char *token) {
    if (!token || strlen(token) == 0) return;
    char *path = get_token_file();
    if (!path) return;
    char *dir = g_path_get_dirname(path);
    g_mkdir_with_parents(dir, 0700);
    g_free(dir);
    g_file_set_contents(path, token, -1, NULL);
    fprintf(stderr, "[knot-shim] Saved InputCapture restore token to %s\n", path);
    g_free(path);
}

static void on_session_started(GObject *source, GAsyncResult *res, gpointer user_data) {
    (void)source;
    ShimContext *ctx = (ShimContext *)user_data;
    GError *error = NULL;
    gboolean ok = xdp_input_capture_session_start_finish(ctx->session, res, &error);

    if (!ok) {
        fprintf(stderr, "[knot-shim] InputCapture start failed: %s\n", error ? error->message : "unknown error");
        GTask *task = g_task_new(G_OBJECT(ctx->portal), ctx->cancellable, ctx->orig_callback, ctx->orig_data);
        g_task_return_error(task, error);
        g_object_unref(task);
    } else {
        const char *token = xdp_input_capture_session_get_restore_token(ctx->session);
        if (token) {
            fprintf(stderr, "[knot-shim] Received restore token: %s\n", token);
            save_token(token);
        } else {
            fprintf(stderr, "[knot-shim] No restore token received from session\n");
        }
        GTask *task = g_task_new(G_OBJECT(ctx->portal), ctx->cancellable, ctx->orig_callback, ctx->orig_data);
        g_task_return_pointer(task, ctx->session, NULL);
        g_object_unref(task);
    }
    g_free(ctx);
}

static void on_session_created(GObject *source, GAsyncResult *res, gpointer user_data) {
    (void)source;
    ShimContext *ctx = (ShimContext *)user_data;
    GError *error = NULL;
    XdpInputCaptureSession *session = xdp_portal_create_input_capture_session2_finish(ctx->portal, res, &error);

    if (!session) {
        fprintf(stderr, "[knot-shim] create_input_capture_session2 failed: %s\n", error ? error->message : "unknown error");
        typeof(xdp_portal_create_input_capture_session) *orig = dlsym(RTLD_NEXT, "xdp_portal_create_input_capture_session");
        if (orig) {
            fprintf(stderr, "[knot-shim] Falling back to standard xdp_portal_create_input_capture_session (API 1)...\n");
            g_clear_error(&error);
            orig(ctx->portal, ctx->parent, ctx->capabilities, ctx->cancellable, ctx->orig_callback, ctx->orig_data);
            g_free(ctx);
            return;
        }
        GTask *task = g_task_new(G_OBJECT(ctx->portal), ctx->cancellable, ctx->orig_callback, ctx->orig_data);
        g_task_return_error(task, error);
        g_object_unref(task);
        g_free(ctx);
        return;
    }

    ctx->session = session;

    // Request persistent session
    xdp_input_capture_session_set_session_persistence(session, XDP_INPUT_CAPTURE_SESSION_PERSISTENCE_PERSISTENT);

    // If we have a saved restore token, set it
    char *token = read_saved_token();
    if (token) {
        fprintf(stderr, "[knot-shim] Reusing saved restore token: %s\n", token);
        xdp_input_capture_session_set_restore_token(session, token);
        g_free(token);
    } else {
        fprintf(stderr, "[knot-shim] No saved restore token found, creating initial persistent session\n");
    }

    // Start the session
    xdp_input_capture_session_start(session, ctx->parent, ctx->capabilities, ctx->cancellable, on_session_started, ctx);
}

void xdp_portal_create_input_capture_session(XdpPortal *portal,
                                             XdpParent *parent,
                                             XdpInputCapability capabilities,
                                             GCancellable *cancellable,
                                             GAsyncReadyCallback callback,
                                             gpointer data) {
    fprintf(stderr, "[knot-shim] Intercepted xdp_portal_create_input_capture_session, upgrading to API 2 with persistence...\n");
    ShimContext *ctx = g_new0(ShimContext, 1);
    ctx->portal = portal;
    ctx->parent = parent;
    ctx->capabilities = capabilities;
    ctx->cancellable = cancellable;
    ctx->orig_callback = callback;
    ctx->orig_data = data;

    xdp_portal_create_input_capture_session2(portal, cancellable, on_session_created, ctx);
}

XdpInputCaptureSession *xdp_portal_create_input_capture_session_finish(XdpPortal *portal,
                                                                      GAsyncResult *result,
                                                                      GError **error) {
    if (G_IS_TASK(result)) {
        return (XdpInputCaptureSession *)g_task_propagate_pointer(G_TASK(result), error);
    }

    typeof(xdp_portal_create_input_capture_session_finish) *orig = dlsym(RTLD_NEXT, "xdp_portal_create_input_capture_session_finish");
    if (orig) {
        return orig(portal, result, error);
    }
    return NULL;
}

GList *xdp_input_capture_session_get_zones(XdpInputCaptureSession *session) {
    typeof(xdp_input_capture_session_get_zones) *orig = dlsym(RTLD_NEXT, "xdp_input_capture_session_get_zones");
    if (!orig) return NULL;
    GList *zones = orig(session);
    g_num_screens = 0;
    fprintf(stderr, "[knot-shim] get_zones returned %u zones:\n", g_list_length(zones));
    for (GList *l = zones; l != NULL && g_num_screens < 16; l = l->next) {
        gint x = 0, y = 0;
        guint w = 0, h = 0;
        g_object_get(l->data, "x", &x, "y", &y, "width", &w, "height", &h, NULL);
        g_screens[g_num_screens].x = x;
        g_screens[g_num_screens].y = y;
        g_screens[g_num_screens].w = w;
        g_screens[g_num_screens].h = h;
        fprintf(stderr, "[knot-shim]   Screen [%d]: %ux%u @ %d,%d\n", g_num_screens, w, h, x, y);
        g_num_screens++;
    }
    return zones;
}

typedef struct {
    guint id;
    int x1;
    int y1;
    int x2;
    int y2;
} CapturedBarrier;

static CapturedBarrier g_captured_barriers[32];
static int g_num_captured_barriers = 0;
static gboolean g_has_captured_barriers = FALSE;
static gboolean install_kwin_barriers(gpointer user_data);

void xdp_input_capture_session_set_pointer_barriers(XdpInputCaptureSession *session,
                                                    GList *barriers,
                                                    GCancellable *cancellable,
                                                    GAsyncReadyCallback callback,
                                                    gpointer data) {
    g_num_captured_barriers = 0;
    g_has_captured_barriers = TRUE;
    guint len = g_list_length(barriers);
    fprintf(stderr, "[knot-shim] set_pointer_barriers called with %u barriers:\n", len);

    for (GList *l = barriers; l != NULL && g_num_captured_barriers < 32; l = l->next) {
        GObject *obj = G_OBJECT(l->data);
        guint id = 0;
        gint x1 = 0, y1 = 0, x2 = 0, y2 = 0;
        g_object_get(obj, "id", &id, "x1", &x1, "y1", &y1, "x2", &x2, "y2", &y2, NULL);
        g_captured_barriers[g_num_captured_barriers].id = id;
        g_captured_barriers[g_num_captured_barriers].x1 = x1;
        g_captured_barriers[g_num_captured_barriers].y1 = y1;
        g_captured_barriers[g_num_captured_barriers].x2 = x2;
        g_captured_barriers[g_num_captured_barriers].y2 = y2;
        fprintf(stderr, "[knot-shim]   Deskflow Barrier [%d]: ID=%u (%d, %d) -> (%d, %d)\n",
                g_num_captured_barriers, id, x1, y1, x2, y2);
        g_num_captured_barriers++;
    }

    typeof(xdp_input_capture_session_set_pointer_barriers) *orig = dlsym(RTLD_NEXT, "xdp_input_capture_session_set_pointer_barriers");
    if (orig) {
        orig(session, barriers, cancellable, callback, data);
    }

    // Schedule direct KWin barrier sync to apply the exact barriers immediately
    g_timeout_add(50, install_kwin_barriers, NULL);
}

GList *xdp_input_capture_session_set_pointer_barriers_finish(XdpInputCaptureSession *session,
                                                            GAsyncResult *result,
                                                            GError **error) {
    typeof(xdp_input_capture_session_set_pointer_barriers_finish) *orig = dlsym(RTLD_NEXT, "xdp_input_capture_session_set_pointer_barriers_finish");
    if (!orig) return NULL;
    GList *failed = orig(session, result, error);
    if (failed) {
        fprintf(stderr, "[knot-shim] Suppressing %u portal failed barriers to preserve Deskflow direction tracking\n", g_list_length(failed));
        g_list_free_full(failed, g_object_unref);
    }
    return NULL; // Return NULL so Deskflow treats all barriers as active!
}

static gboolean install_kwin_barriers(gpointer user_data) {
    (void)user_data;
    GError *error = NULL;
    GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, &error);
    if (!bus) {
        fprintf(stderr, "[knot-shim] install_kwin_barriers: Failed to connect to session bus: %s\n",
                error ? error->message : "unknown");
        return G_SOURCE_REMOVE;
    }

    GVariant *reply = g_dbus_connection_call_sync(
        bus,
        "org.kde.KWin",
        "/org/kde/KWin/EIS/InputCapture",
        "org.freedesktop.DBus.Introspectable",
        "Introspect",
        NULL,
        G_VARIANT_TYPE("(s)"),
        G_DBUS_CALL_FLAGS_NONE,
        1000,
        NULL,
        &error
    );

    if (!reply) {
        fprintf(stderr, "[knot-shim] install_kwin_barriers: Failed to introspect KWin: %s\n",
                error ? error->message : "unknown");
        g_object_unref(bus);
        return G_SOURCE_REMOVE;
    }

    const char *xml = NULL;
    g_variant_get(reply, "(&s)", &xml);

    int highest_id = -1;
    const char *p = xml;
    while ((p = strstr(p, "<node name=\"")) != NULL) {
        p += 12;
        char name[64] = {0};
        int i = 0;
        while (*p && *p != '"' && i < 63) {
            name[i++] = *p++;
        }
        name[i] = '\0';
        int all_digits = 1;
        for (int j = 0; j < i; j++) {
            if (name[j] < '0' || name[j] > '9') { all_digits = 0; break; }
        }
        if (all_digits && i > 0) {
            int val = atoi(name);
            if (val > highest_id) {
                highest_id = val;
            }
        }
    }
    g_variant_unref(reply);

    if (highest_id < 0) {
        fprintf(stderr, "[knot-shim] install_kwin_barriers: No active KWin InputCapture session node found\n");
        g_object_unref(bus);
        return G_SOURCE_REMOVE;
    }

    char session_path[256];
    snprintf(session_path, sizeof(session_path), "/org/kde/KWin/EIS/InputCapture/%d", highest_id);
    fprintf(stderr, "[knot-shim] Direct KWin InputCapture target: %s\n", session_path);

    GVariantBuilder builder;
    g_variant_builder_init(&builder, G_VARIANT_TYPE("a(u(ii)(ii))"));
    int barrier_count = 0;

    if (g_has_captured_barriers) {
        for (int i = 0; i < g_num_captured_barriers; i++) {
            CapturedBarrier *b = &g_captured_barriers[i];
            int x1 = b->x1, y1 = b->y1, x2 = b->x2, y2 = b->y2;

            // KWin expects inclusive pixel coordinates on the active monitor canvas (e.g. 0..w-1, 0..h-1).
            // Deskflow generates 1-past-the-end coordinates for Bottom (y = y + h) and Right (x = x + w).
            // Adjust them to the edge pixel so KWin's hitTest(QPointF) exact coordinate check matches!
            for (int s = 0; s < g_num_screens; s++) {
                if (y1 == y2 && y1 == g_screens[s].y + g_screens[s].h) {
                    y1 = g_screens[s].y + g_screens[s].h - 1;
                    y2 = y1;
                    break;
                }
            }
            for (int s = 0; s < g_num_screens; s++) {
                if (x1 == x2 && x1 == g_screens[s].x + g_screens[s].w) {
                    x1 = g_screens[s].x + g_screens[s].w - 1;
                    x2 = x1;
                    break;
                }
            }

            g_variant_builder_add(&builder, "(u(ii)(ii))", b->id, x1, y1, x2, y2);
            fprintf(stderr, "[knot-shim]   KWin Barrier ID=%u: (%d, %d) -> (%d, %d)\n",
                    b->id, x1, y1, x2, y2);
            barrier_count++;
        }
    }

    GVariant *barriers_var = g_variant_builder_end(&builder);
    GVariant *params = g_variant_new_tuple(&barriers_var, 1);

    GVariant *enable_reply = g_dbus_connection_call_sync(
        bus,
        "org.kde.KWin",
        session_path,
        "org.kde.KWin.EIS.InputCapture",
        "enable",
        params,
        NULL,
        G_DBUS_CALL_FLAGS_NONE,
        1000,
        NULL,
        &error
    );

    if (!enable_reply) {
        fprintf(stderr, "[knot-shim] Failed to call enable on %s: %s\n", session_path, error ? error->message : "unknown");
    } else {
        fprintf(stderr, "[knot-shim] Successfully installed %d custom barriers into KWin!\n", barrier_count);
        g_variant_unref(enable_reply);
    }

    g_object_unref(bus);
    return G_SOURCE_REMOVE;
}

void xdp_input_capture_session_enable(XdpInputCaptureSession *session) {
    typeof(xdp_input_capture_session_enable) *orig = dlsym(RTLD_NEXT, "xdp_input_capture_session_enable");
    if (orig) {
        orig(session);
    }
    fprintf(stderr, "[knot-shim] Intercepted xdp_input_capture_session_enable, scheduling direct KWin barrier sync in 100ms...\n");
    g_timeout_add(100, install_kwin_barriers, NULL);
}
