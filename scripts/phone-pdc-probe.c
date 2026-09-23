/*
 * Read-only QMI PDC inventory over QRTR: the selected software configuration,
 * the resident software configurations and each one's description, version and
 * size. It never loads, selects, activates, deactivates or deletes anything, and
 * it does not request the platform list that crashed qmicli 1.38 on this phone.
 *
 * Every step waits at most STEP_SECONDS and the process has a hard watchdog.
 * Exiting closes the QRTR socket, which also releases the modem-side client.
 *
 * Build on the phone:
 *   gcc -O2 -Wall -o pdc-probe phone-pdc-probe.c $(pkg-config --cflags --libs qmi-glib qrtr-glib)
 */
#include <libqmi-glib.h>
#include <libqrtr-glib.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define STEP_SECONDS 10
#define WATCHDOG_SECONDS 90
#define MODEM_NODE 0

typedef struct {
    GAsyncResult *res;
    gpointer indication;
    guint32 token;
    gboolean timed_out;
} Wait;

static gboolean on_timeout(gpointer data)
{
    ((Wait *)data)->timed_out = TRUE;
    return G_SOURCE_REMOVE;
}

static void ready(GObject *source, GAsyncResult *res, gpointer data)
{
    ((Wait *)data)->res = g_object_ref(res);
}

/* Iterate until the reply (or matching indication) arrives; a timeout is fatal. */
static void run(Wait *w, gboolean indication, const char *step)
{
    guint id = g_timeout_add_seconds(STEP_SECONDS, on_timeout, w);

    while (!w->timed_out && !(indication ? w->indication != NULL : w->res != NULL))
        g_main_context_iteration(NULL, TRUE);
    if (w->timed_out) {
        printf("%s: no answer within %d s\n", step, STEP_SECONDS);
        exit(3);
    }
    g_source_remove(id);
}

static void fail(const char *step, GError *error)
{
    printf("%s: %s\n", step, error ? error->message : "failed");
    exit(2);
}

static char *hex(GArray *bytes)
{
    GString *out = g_string_new(NULL);

    for (guint i = 0; bytes && i < bytes->len; i++)
        g_string_append_printf(out, "%02x", g_array_index(bytes, guint8, i));
    return g_string_free(out, FALSE);
}

static void on_selected(QmiClientPdc *client, QmiIndicationPdcGetSelectedConfigOutput *output, Wait *w)
{
    guint32 token = 0;

    if (!w->indication && qmi_indication_pdc_get_selected_config_output_get_token(output, &token, NULL) &&
        token == w->token)
        w->indication = qmi_indication_pdc_get_selected_config_output_ref(output);
}

static void on_list(QmiClientPdc *client, QmiIndicationPdcListConfigsOutput *output, Wait *w)
{
    guint32 token = 0;

    if (!w->indication && qmi_indication_pdc_list_configs_output_get_token(output, &token, NULL) &&
        token == w->token)
        w->indication = qmi_indication_pdc_list_configs_output_ref(output);
}

static void on_info(QmiClientPdc *client, QmiIndicationPdcGetConfigInfoOutput *output, Wait *w)
{
    guint32 token = 0;

    if (!w->indication && qmi_indication_pdc_get_config_info_output_get_token(output, &token, NULL) &&
        token == w->token)
        w->indication = qmi_indication_pdc_get_config_info_output_ref(output);
}

static void selected_config(QmiClientPdc *pdc, Wait *w)
{
    g_autoptr(QmiMessagePdcGetSelectedConfigInput) input = qmi_message_pdc_get_selected_config_input_new();
    g_autoptr(QmiMessagePdcGetSelectedConfigOutput) output = NULL;
    g_autoptr(GError) error = NULL;
    GArray *active = NULL, *pending = NULL;
    guint16 code = 0;

    w->token = 1;
    qmi_message_pdc_get_selected_config_input_set_config_type(input, QMI_PDC_CONFIGURATION_TYPE_SOFTWARE, NULL);
    qmi_message_pdc_get_selected_config_input_set_token(input, w->token, NULL);
    qmi_client_pdc_get_selected_config(pdc, input, STEP_SECONDS, NULL, ready, w);
    run(w, FALSE, "get-selected");
    output = qmi_client_pdc_get_selected_config_finish(pdc, w->res, &error);
    if (!output || !qmi_message_pdc_get_selected_config_output_get_result(output, &error)) {
        printf("get-selected: request refused: %s\n", error->message);
        return;
    }
    run(w, TRUE, "get-selected indication");
    qmi_indication_pdc_get_selected_config_output_get_indication_result(w->indication, &code, NULL);
    if (code) {
        printf("get-selected: %s (%u)\n", qmi_protocol_error_get_string(code), code);
        return;
    }
    qmi_indication_pdc_get_selected_config_output_get_active_id(w->indication, &active, NULL);
    qmi_indication_pdc_get_selected_config_output_get_pending_id(w->indication, &pending, NULL);
    printf("get-selected: active=%s pending=%s\n", active ? hex(active) : "-", pending ? hex(pending) : "-");
}

static GArray *list_configs(QmiClientPdc *pdc, Wait *w)
{
    g_autoptr(QmiMessagePdcListConfigsInput) input = qmi_message_pdc_list_configs_input_new();
    g_autoptr(QmiMessagePdcListConfigsOutput) output = NULL;
    g_autoptr(GError) error = NULL;
    GArray *configs = NULL;
    guint16 code = 0;

    w->token = 2;
    qmi_message_pdc_list_configs_input_set_config_type(input, QMI_PDC_CONFIGURATION_TYPE_SOFTWARE, NULL);
    qmi_message_pdc_list_configs_input_set_token(input, w->token, NULL);
    qmi_client_pdc_list_configs(pdc, input, STEP_SECONDS, NULL, ready, w);
    run(w, FALSE, "list-software");
    output = qmi_client_pdc_list_configs_finish(pdc, w->res, &error);
    if (!output || !qmi_message_pdc_list_configs_output_get_result(output, &error)) {
        printf("list-software: request refused: %s\n", error->message);
        return NULL;
    }
    run(w, TRUE, "list-software indication");
    qmi_indication_pdc_list_configs_output_get_indication_result(w->indication, &code, NULL);
    if (code) {
        printf("list-software: %s (%u)\n", qmi_protocol_error_get_string(code), code);
        return NULL;
    }
    if (!qmi_indication_pdc_list_configs_output_get_configs(w->indication, &configs, NULL) || !configs) {
        printf("list-software: no configuration list in the answer\n");
        return NULL;
    }
    printf("list-software: %u resident configurations\n", configs->len);
    return configs;
}

static void config_info(QmiClientPdc *pdc, Wait *w, guint index, QmiPdcConfigurationType type, GArray *id)
{
    g_autoptr(QmiMessagePdcGetConfigInfoInput) input = qmi_message_pdc_get_config_info_input_new();
    g_autoptr(QmiMessagePdcGetConfigInfoOutput) output = NULL;
    g_autoptr(GError) error = NULL;
    g_autofree char *id_hex = hex(id);
    const gchar *description = NULL;
    guint32 version = 0, size = 0;
    guint16 code = 0;

    w->token = 100 + index;
    qmi_message_pdc_get_config_info_input_set_type_with_id_v2(input, type, id, NULL);
    qmi_message_pdc_get_config_info_input_set_token(input, w->token, NULL);
    qmi_client_pdc_get_config_info(pdc, input, STEP_SECONDS, NULL, ready, w);
    run(w, FALSE, "config-info");
    output = qmi_client_pdc_get_config_info_finish(pdc, w->res, &error);
    if (!output || !qmi_message_pdc_get_config_info_output_get_result(output, &error)) {
        printf("config %u id=%s: request refused: %s\n", index, id_hex, error->message);
        return;
    }
    run(w, TRUE, "config-info indication");
    qmi_indication_pdc_get_config_info_output_get_indication_result(w->indication, &code, NULL);
    if (code) {
        printf("config %u id=%s: %s (%u)\n", index, id_hex, qmi_protocol_error_get_string(code), code);
        return;
    }
    qmi_indication_pdc_get_config_info_output_get_description(w->indication, &description, NULL);
    qmi_indication_pdc_get_config_info_output_get_version(w->indication, &version, NULL);
    qmi_indication_pdc_get_config_info_output_get_total_size(w->indication, &size, NULL);
    printf("config %u id=%s version=0x%08x size=%u description=%s\n", index, id_hex, version, size,
           description ? description : "-");
}

static void reset(Wait *w)
{
    g_clear_object(&w->res);
    w->indication = NULL;
    w->timed_out = FALSE;
}

int main(void)
{
    g_autoptr(GError) error = NULL;
    g_autoptr(QrtrBus) bus = NULL;
    g_autoptr(QrtrNode) node = NULL;
    g_autoptr(QmiDevice) device = NULL;
    g_autoptr(QmiClient) client = NULL;
    GArray *configs;
    Wait w = { 0 };

    setvbuf(stdout, NULL, _IOLBF, 0);
    alarm(WATCHDOG_SECONDS);

    qrtr_bus_new(1000, NULL, ready, &w);
    run(&w, FALSE, "qrtr-bus");
    if (!(bus = qrtr_bus_new_finish(w.res, &error)))
        fail("qrtr-bus", error);
    if (!(node = qrtr_bus_get_node(bus, MODEM_NODE)))
        fail("qrtr-node", NULL);
    reset(&w);
    qmi_device_new_from_node(node, NULL, ready, &w);
    run(&w, FALSE, "qmi-device");
    if (!(device = qmi_device_new_from_node_finish(w.res, &error)))
        fail("qmi-device", error);
    reset(&w);
    qmi_device_open(device, QMI_DEVICE_OPEN_FLAGS_NONE, STEP_SECONDS, NULL, ready, &w);
    run(&w, FALSE, "qmi-open");
    if (!qmi_device_open_finish(device, w.res, &error))
        fail("qmi-open", error);
    reset(&w);
    qmi_device_allocate_client(device, QMI_SERVICE_PDC, QMI_CID_NONE, STEP_SECONDS, NULL, ready, &w);
    run(&w, FALSE, "pdc-client");
    if (!(client = qmi_device_allocate_client_finish(device, w.res, &error)))
        fail("pdc-client", error);

    g_signal_connect(client, "get-selected-config", G_CALLBACK(on_selected), &w);
    g_signal_connect(client, "list-configs", G_CALLBACK(on_list), &w);
    g_signal_connect(client, "get-config-info", G_CALLBACK(on_info), &w);

    reset(&w);
    selected_config(QMI_CLIENT_PDC(client), &w);
    reset(&w);
    configs = list_configs(QMI_CLIENT_PDC(client), &w);
    for (guint i = 0; configs && i < configs->len; i++) {
        QmiIndicationPdcListConfigsOutputConfigsElement *element =
            &g_array_index(configs, QmiIndicationPdcListConfigsOutputConfigsElement, i);

        reset(&w);
        config_info(QMI_CLIENT_PDC(client), &w, i, element->config_type, element->id);
    }

    reset(&w);
    qmi_device_release_client(device, client, QMI_DEVICE_RELEASE_CLIENT_FLAGS_RELEASE_CID, STEP_SECONDS, NULL,
                              ready, &w);
    run(&w, FALSE, "pdc-release");
    if (!qmi_device_release_client_finish(device, w.res, &error))
        fail("pdc-release", error);
    printf("done: client released\n");
    return 0;
}
