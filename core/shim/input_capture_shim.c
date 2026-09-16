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
