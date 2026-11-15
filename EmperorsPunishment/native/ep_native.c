#include <windows.h>
#include <winhttp.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define EXPORT __declspec(dllexport)
#define QUEUE_MAX 32
#define MSG_MAX_AGE_MS 3000
#define PING_INTERVAL_MS 30000
#define RETRY_MS 5000
#define HTTP_BODY_MAX (4 << 20)

enum { WS_DISCONNECTED, WS_CONNECTING, WS_CONNECTED, WS_FAILED };
enum { HTTP_IDLE, HTTP_PENDING, HTTP_DONE };

struct msg {
    char *text;
    ULONGLONG t;
};

static CRITICAL_SECTION lock;
static CRITICAL_SECTION send_lock;
static HANDLE wake_ws, wake_send;
static int started;

static char *ws_url;
static unsigned ws_gen;
static HINTERNET ws_session, ws_connect, ws_handle;
static volatile LONG ws_status;

static struct msg queue[QUEUE_MAX];
static int q_head, q_count;

static char last_error[512];
static int has_error;

static int http_state, http_status, http_len;
static char *http_body, *http_url, *http_headers, *http_post;

static void set_error(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    EnterCriticalSection(&lock);
    vsnprintf(last_error, sizeof last_error, fmt, args);
    has_error = 1;
    LeaveCriticalSection(&lock);
    va_end(args);
}

static WCHAR *wide(const char *s) {
    int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
    WCHAR *w = malloc(n * sizeof(WCHAR));
    MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
    return w;
}

static void close_handles(HINTERNET a, HINTERNET b, HINTERNET c) {
    if (a) WinHttpCloseHandle(a);
    if (b) WinHttpCloseHandle(b);
    if (c) WinHttpCloseHandle(c);
}

static HINTERNET open_request(const char *url, const WCHAR *verb, HINTERNET *session, HINTERNET *connect, int recv_timeout) {
    WCHAR *wurl = wide(url);
    WCHAR host[256];
    URL_COMPONENTS uc;
    HINTERNET request = NULL;

    *session = *connect = NULL;
    memset(&uc, 0, sizeof uc);
    uc.dwStructSize = sizeof uc;
    uc.lpszHostName = host;
    uc.dwHostNameLength = 256;
    uc.dwUrlPathLength = (DWORD)-1;

    if (WinHttpCrackUrl(wurl, 0, 0, &uc)) {
        *session = WinHttpOpen(L"EmperorsPunishment-Darktide", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, NULL, NULL, 0);
        if (*session) {
            WinHttpSetTimeouts(*session, 5000, 5000, 5000, recv_timeout);
            *connect = WinHttpConnect(*session, host, uc.nPort, 0);
        }
        if (*connect) {
            request = WinHttpOpenRequest(*connect, verb, uc.lpszUrlPath, NULL, NULL, NULL,
                                         uc.nScheme == INTERNET_SCHEME_HTTPS ? WINHTTP_FLAG_SECURE : 0);
        }
    }
    free(wurl);
    return request;
}

static DWORD WINAPI http_thread(LPVOID param) {
    HINTERNET session, connect, request;
    WCHAR *headers = http_headers[0] ? wide(http_headers) : NULL;
    char *body = NULL;
    int len = 0, cap = 0, status = 0;
    DWORD post_len = http_post ? (DWORD)strlen(http_post) : 0;

    (void)param;
    request = open_request(http_url, http_post ? L"POST" : L"GET", &session, &connect, 10000);
    if (request &&
        WinHttpSendRequest(request, headers ? headers : WINHTTP_NO_ADDITIONAL_HEADERS, headers ? (DWORD)-1 : 0,
                           http_post ? http_post : WINHTTP_NO_REQUEST_DATA, post_len, post_len, 0) &&
        WinHttpReceiveResponse(request, NULL)) {
        DWORD code = 0, size = sizeof code;
        WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, NULL, &code, &size, NULL);
        status = (int)code;
        while (len < HTTP_BODY_MAX) {
            DWORD got = 0;
            if (len + 8192 > cap) {
                cap = cap ? cap * 2 : 16384;
                body = realloc(body, cap);
            }
            if (!WinHttpReadData(request, body + len, 8192, &got)) {
                status = -(int)GetLastError();
                len = 0;
                break;
            }
            if (!got) break;
            len += (int)got;
        }
    } else {
        status = -(int)GetLastError();
    }
    close_handles(request, connect, session);
    free(headers);

    EnterCriticalSection(&lock);
    free(http_body);
    http_body = body;
    http_len = len;
    http_status = status;
    http_state = HTTP_DONE;
    LeaveCriticalSection(&lock);
    return 0;
}

static DWORD WINAPI ws_thread(LPVOID param) {
    (void)param;
    for (;;) {
        HINTERNET session, connect, request, handle = NULL;
        DWORD err = 0, http = 0, size = sizeof http;
        char *url = NULL;
        char buf[4096];
        unsigned gen;
        int n = 0, mine, auth_failed = 0;

        EnterCriticalSection(&lock);
        if (ws_url) url = _strdup(ws_url);
        gen = ws_gen;
        LeaveCriticalSection(&lock);

        if (!url) {
            if (ws_status != WS_FAILED) ws_status = WS_DISCONNECTED;
            WaitForSingleObject(wake_ws, INFINITE);
            continue;
        }

        ws_status = WS_CONNECTING;
        request = open_request(url, L"GET", &session, &connect, 90000);
        free(url);
        if (request &&
            WinHttpSetOption(request, WINHTTP_OPTION_UPGRADE_TO_WEB_SOCKET, NULL, 0) &&
            WinHttpSendRequest(request, WINHTTP_NO_ADDITIONAL_HEADERS, 0, NULL, 0, 0, 0) &&
            WinHttpReceiveResponse(request, NULL)) {
            handle = WinHttpWebSocketCompleteUpgrade(request, 0);
            if (!handle) {
                err = GetLastError();
                WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER, NULL, &http, &size, NULL);
            }
        } else {
            err = GetLastError();
        }
        if (request) WinHttpCloseHandle(request);

        if (!handle) {
            close_handles(connect, session, NULL);
            EnterCriticalSection(&lock);
            if (gen == ws_gen) {
                ws_status = WS_FAILED;
                set_error("Could not connect to PiShock (error %lu, HTTP %lu).", err, http);
            }
            LeaveCriticalSection(&lock);
            WaitForSingleObject(wake_ws, RETRY_MS);
            continue;
        }

        EnterCriticalSection(&lock);
        if (gen != ws_gen) {
            LeaveCriticalSection(&lock);
            close_handles(handle, connect, session);
            continue;
        }
        ws_handle = handle;
        ws_connect = connect;
        ws_session = session;
        ws_status = WS_CONNECTED;
        LeaveCriticalSection(&lock);
        SetEvent(wake_send);

        for (;;) {
            DWORD got = 0;
            WINHTTP_WEB_SOCKET_BUFFER_TYPE type = 0;
            if (WinHttpWebSocketReceive(handle, buf + n, (DWORD)(sizeof buf - 1 - n), &got, &type) != ERROR_SUCCESS ||
                type == WINHTTP_WEB_SOCKET_CLOSE_BUFFER_TYPE) {
                break;
            }
            n += (int)got;
            if (type == WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE ||
                type == WINHTTP_WEB_SOCKET_BINARY_MESSAGE_BUFFER_TYPE || n >= (int)sizeof buf - 1) {
                buf[n] = 0;
                EnterCriticalSection(&lock);
                if (gen == ws_gen) {
                    if (strstr(buf, "\"IsError\":true")) set_error("%.400s", buf);
                    if (strstr(buf, "AUTH_ERROR")) auth_failed = 1;
                }
                LeaveCriticalSection(&lock);
                n = 0;
            }
        }

        EnterCriticalSection(&send_lock);
        EnterCriticalSection(&lock);
        mine = ws_handle == handle;
        if (mine) {
            ws_handle = ws_connect = ws_session = NULL;
            ws_status = auth_failed ? WS_FAILED : WS_DISCONNECTED;
            if (auth_failed) {
                free(ws_url);
                ws_url = NULL;
                ws_gen++;
            }
        }
        LeaveCriticalSection(&lock);
        LeaveCriticalSection(&send_lock);

        if (mine) {
            close_handles(handle, connect, session);
            WaitForSingleObject(wake_ws, 1000);
        }
    }
}

static char *pop_message(void) {
    char *text = queue[q_head].text;
    q_head = (q_head + 1) % QUEUE_MAX;
    q_count--;
    return text;
}

static DWORD WINAPI send_thread(LPVOID param) {
    ULONGLONG last_send = GetTickCount64();

    (void)param;
    for (;;) {
        WaitForSingleObject(wake_send, 1000);
        for (;;) {
            HINTERNET handle;
            char *text = NULL;
            ULONGLONG now;

            EnterCriticalSection(&send_lock);
            EnterCriticalSection(&lock);
            handle = ws_handle;
            now = GetTickCount64();
            while (q_count && now - queue[q_head].t > MSG_MAX_AGE_MS) free(pop_message());
            if (handle && q_count) {
                text = pop_message();
            } else if (handle && now - last_send > PING_INTERVAL_MS) {
                text = _strdup("{\"Operation\":\"PING\"}");
            }
            LeaveCriticalSection(&lock);

            if (text) {
                DWORD err = WinHttpWebSocketSend(handle, WINHTTP_WEB_SOCKET_UTF8_MESSAGE_BUFFER_TYPE, text, (DWORD)strlen(text));
                if (err != ERROR_SUCCESS) set_error("Sending to PiShock failed (error %lu).", err);
                free(text);
                last_send = GetTickCount64();
            }
            LeaveCriticalSection(&send_lock);
            if (!text) break;
        }
    }
}

static void set_target(const char *url) {
    HINTERNET handle, connect, session;

    EnterCriticalSection(&send_lock);
    EnterCriticalSection(&lock);
    free(ws_url);
    ws_url = url ? _strdup(url) : NULL;
    ws_gen++;
    handle = ws_handle;
    connect = ws_connect;
    session = ws_session;
    ws_handle = ws_connect = ws_session = NULL;
    while (q_count) free(pop_message());
    has_error = 0;
    if (!started) {
        started = 1;
        CloseHandle(CreateThread(NULL, 0, ws_thread, NULL, 0, NULL));
        CloseHandle(CreateThread(NULL, 0, send_thread, NULL, 0, NULL));
    }
    LeaveCriticalSection(&lock);
    LeaveCriticalSection(&send_lock);

    close_handles(handle, connect, session);
    SetEvent(wake_ws);
}

EXPORT int EP_Connect(const char *url) {
    char *target;
    int same;

    if (!url || !url[0]) return 0;
    target = malloc(strlen(url) + 8);
    if (!strncmp(url, "wss://", 6)) {
        sprintf(target, "https://%s", url + 6);
    } else {
        strcpy(target, url);
    }

    EnterCriticalSection(&lock);
    same = ws_url && !strcmp(ws_url, target);
    LeaveCriticalSection(&lock);

    if (!same) set_target(target);
    free(target);
    return 1;
}

EXPORT void EP_Disconnect(void) {
    set_target(NULL);
}

EXPORT int EP_Status(void) {
    return (int)ws_status;
}

EXPORT int EP_Send(const char *text) {
    int ok = 0;

    EnterCriticalSection(&lock);
    if (ws_url && text && q_count < QUEUE_MAX) {
        struct msg *m = &queue[(q_head + q_count) % QUEUE_MAX];
        m->text = _strdup(text);
        m->t = GetTickCount64();
        q_count++;
        ok = 1;
    }
    LeaveCriticalSection(&lock);
    if (ok) SetEvent(wake_send);
    return ok;
}

EXPORT int EP_LastError(char *buffer, int buffer_size) {
    int n = 0;

    EnterCriticalSection(&lock);
    if (has_error && buffer_size > 0) {
        n = (int)strlen(last_error);
        if (n > buffer_size) n = buffer_size;
        memcpy(buffer, last_error, n);
        has_error = 0;
    }
    LeaveCriticalSection(&lock);
    return n;
}

static int http_start(const char *url, const char *headers, const char *post) {
    int ok = 0;

    EnterCriticalSection(&lock);
    if (http_state != HTTP_PENDING && url) {
        free(http_url);
        free(http_headers);
        http_url = _strdup(url);
        http_headers = _strdup(headers ? headers : "");
        free(http_post);
        http_post = post ? _strdup(post) : NULL;
        http_state = HTTP_PENDING;
        ok = 1;
    }
    LeaveCriticalSection(&lock);
    if (ok) CloseHandle(CreateThread(NULL, 0, http_thread, NULL, 0, NULL));
    return ok;
}

EXPORT int EP_HttpGet(const char *url, const char *headers) {
    return http_start(url, headers, NULL);
}

EXPORT int EP_HttpPost(const char *url, const char *headers, const char *body) {
    return http_start(url, headers, body ? body : "");
}

EXPORT int EP_HttpState(void) {
    int state;

    EnterCriticalSection(&lock);
    state = http_state;
    LeaveCriticalSection(&lock);
    return state;
}

EXPORT int EP_HttpResult(char *buffer, int buffer_size, int *status) {
    int n = 0;

    EnterCriticalSection(&lock);
    if (http_state == HTTP_DONE) {
        if (http_len > buffer_size) {
            n = -http_len;
        } else {
            n = http_len;
            if (n) memcpy(buffer, http_body, n);
            if (status) *status = http_status;
            http_state = HTTP_IDLE;
        }
    }
    LeaveCriticalSection(&lock);
    return n;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    (void)reserved;
    if (reason == DLL_PROCESS_ATTACH) {
        HMODULE pinned;
        InitializeCriticalSection(&lock);
        InitializeCriticalSection(&send_lock);
        wake_ws = CreateEventW(NULL, FALSE, FALSE, NULL);
        wake_send = CreateEventW(NULL, FALSE, FALSE, NULL);
        GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_PIN | GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS, (LPCWSTR)instance, &pinned);
    }
    return TRUE;
}
