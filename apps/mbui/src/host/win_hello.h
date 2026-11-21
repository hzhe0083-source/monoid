// Windows Hello, as the core's secure.* asks the person (win_core.c; apple_core.mm's LocalAuthentication on the Mac):
// Windows.Security.Credentials.UI.UserConsentVerifier through WinRT's C ABI, in C (no C++ runtime: win.sh's check_crt
// refuses the Visual C++ redistributable), runtimeobject.lib the system's own (api-ms-win-core-winrt-*, combase).
//   win_hello_check()                 NULL when the person can be asked here (Hello set up: a PIN, a face, a finger),
//                                     else why not, as the core's hosts say it (client/core-ts/src/host-of.ts secureGet)
//   win_hello_ask(window, reason)     the person asked over `window` (IUserConsentVerifierInterop, the desktop's way:
//                                     RequestVerificationAsync is a UWP app's), `reason` in the prompt, their answer
//                                     waited for (so only on a thread that may wait: win_core.c's person thread): NULL
//                                     once they said yes, else why not
// Why not: `user_cancelled` (the person said no, or failed it), `no_device_lock` (no Hello here: nothing can need the
// person), `not_in_front` (no window shown to ask over, or Hello busy), else `windows_hello_0x<HRESULT>`.
// The async operations' completions are waited for on an event their handler sets (agile: called on a pool thread).
// Each IID is its own here: the SDK's C headers declare the parameterized ones without defining them anywhere, and
// userconsentverifierinterop.h shows its interface only from NTDDI_WIN10_RS3 (win_core.c is built for 0x0A00). The
// parameterized ones are WinRT's (pinterface: SHA-1 of its namespace and the signature), checked by core/hello_test_win.c.
#ifndef MBUI_WIN_HELLO_H
#define MBUI_WIN_HELLO_H
#ifndef COBJMACROS
#define COBJMACROS
#endif
#include <windows.h>
#include <objbase.h>
#pragma warning(push, 3)
#include <roapi.h>
#include <winstring.h>
#include <windows.security.credentials.ui.h>
#pragma warning(pop)
#include <stdio.h>
#include <stdlib.h>

#pragma comment(lib, "runtimeobject.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "uuid.lib")

typedef __x_ABI_CWindows_CSecurity_CCredentials_CUI_CIUserConsentVerifierStatics win_hello_statics;
typedef __FIAsyncOperation_1_Windows__CSecurity__CCredentials__CUI__CUserConsentVerifierAvailability win_hello_avail_op;
typedef __FIAsyncOperation_1_Windows__CSecurity__CCredentials__CUI__CUserConsentVerificationResult win_hello_result_op;

// Windows.Security.Credentials.UI.IUserConsentVerifierStatics
static const IID WIN_HELLO_IID_STATICS = {0xaf4f3f91, 0x564c, 0x4ddc, {0xb8, 0xb5, 0x97, 0x34, 0x47, 0x62, 0x7c, 0x65}};
// IUserConsentVerifierInterop (userconsentverifierinterop.h)
static const IID WIN_HELLO_IID_INTEROP = {0x39e050c3, 0x4e74, 0x441a, {0x8d, 0xc0, 0xb8, 0x11, 0x04, 0xdf, 0x94, 0x9c}};
// IAsyncOperation<UserConsentVerifierAvailability>, its IAsyncOperationCompletedHandler
static const IID WIN_HELLO_IID_AVAIL_OP = {0xddd384f3, 0xd818, 0x5d83, {0xab, 0x4b, 0x32, 0x11, 0x9c, 0x28, 0x58, 0x7c}};
static const IID WIN_HELLO_IID_AVAIL_DONE = {0x28988174, 0xace2, 0x5c15, {0xa0, 0xdf, 0x58, 0x0a, 0x26, 0xd9, 0x42, 0x94}};
// IAsyncOperation<UserConsentVerificationResult>, its IAsyncOperationCompletedHandler
static const IID WIN_HELLO_IID_RESULT_OP = {0xfd596ffd, 0x2318, 0x558f, {0x9d, 0xbe, 0xd2, 0x1d, 0xf4, 0x37, 0x64, 0xa5}};
static const IID WIN_HELLO_IID_RESULT_DONE = {0x0cffc6c9, 0x4c2b, 0x5cd4, {0xb3, 0x8c, 0x7b, 0x8d, 0xf3, 0xff, 0x5a, 0xfb}};
// IAgileObject, IAsyncInfo
static const IID WIN_HELLO_IID_AGILE = {0x94ea2b94, 0xe9cc, 0x49e0, {0xc0, 0xff, 0xee, 0x64, 0xca, 0x8f, 0x5b, 0x90}};
static const IID WIN_HELLO_IID_ASYNC_INFO = {0x00000036, 0x0000, 0x0000, {0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}};

// IUserConsentVerifierInterop, as userconsentverifierinterop.h has it (IInspectable, then its one method)
typedef struct win_hello_interop win_hello_interop;
typedef struct {
  HRESULT(STDMETHODCALLTYPE *QueryInterface)(win_hello_interop *, REFIID, void **);
  ULONG(STDMETHODCALLTYPE *AddRef)(win_hello_interop *);
  ULONG(STDMETHODCALLTYPE *Release)(win_hello_interop *);
  HRESULT(STDMETHODCALLTYPE *GetIids)(win_hello_interop *, ULONG *, IID **);
  HRESULT(STDMETHODCALLTYPE *GetRuntimeClassName)(win_hello_interop *, HSTRING *);
  HRESULT(STDMETHODCALLTYPE *GetTrustLevel)(win_hello_interop *, TrustLevel *);
  HRESULT(STDMETHODCALLTYPE *RequestVerificationForWindowAsync)(win_hello_interop *, HWND, HSTRING, REFIID, void **);
} win_hello_interop_vtbl;
struct win_hello_interop {
  const win_hello_interop_vtbl *lpVtbl;
};

// ── what Windows said, as the core's hosts say it ──

// Why the person cannot be asked here (UserConsentVerifierAvailability), NULL when they can.
static const char *win_hello_availability_error(int avail) {
  switch (avail) {
    case UserConsentVerifierAvailability_Available: return NULL;
    case UserConsentVerifierAvailability_DeviceBusy: return "not_in_front";
    case UserConsentVerifierAvailability_DeviceNotPresent:
    case UserConsentVerifierAvailability_NotConfiguredForUser:
    case UserConsentVerifierAvailability_DisabledByPolicy:
    default: return "no_device_lock";
  }
}

// What the person's answer comes to (UserConsentVerificationResult): NULL once they said yes.
static const char *win_hello_result_error(int res) {
  switch (res) {
    case UserConsentVerificationResult_Verified: return NULL;
    case UserConsentVerificationResult_Canceled:
    case UserConsentVerificationResult_RetriesExhausted: return "user_cancelled";
    case UserConsentVerificationResult_DeviceBusy: return "not_in_front";
    case UserConsentVerificationResult_DeviceNotPresent:
    case UserConsentVerificationResult_NotConfiguredForUser:
    case UserConsentVerificationResult_DisabledByPolicy:
    default: return "no_device_lock";
  }
}

// A failure of the call itself, said as its code where it is none of the others (a thread's own buffer: each thread
// that asks keeps its answer until it asks again).
static const char *win_hello_hresult_error(HRESULT hr) {
  static __declspec(thread) char why[32];
  if (SUCCEEDED(hr)) return NULL;
  if (hr == E_ABORT || hr == HRESULT_FROM_WIN32(ERROR_CANCELLED)) return "user_cancelled";
  if (hr == REGDB_E_CLASSNOTREG || hr == E_NOINTERFACE || hr == CLASS_E_CLASSNOTAVAILABLE) return "no_device_lock";
  if (hr == E_ACCESSDENIED || hr == HRESULT_FROM_WIN32(ERROR_INVALID_WINDOW_HANDLE)) return "not_in_front";
  snprintf(why, sizeof why, "windows_hello_0x%08lx", (unsigned long)hr);
  return why;
}

// ── an async operation's completion, waited for ──

// The completed handler of either operation (their vtables are the same: IUnknown, then Invoke), `iid` the one it is.
typedef struct win_hello_done win_hello_done;
typedef struct {
  HRESULT(STDMETHODCALLTYPE *QueryInterface)(win_hello_done *, REFIID, void **);
  ULONG(STDMETHODCALLTYPE *AddRef)(win_hello_done *);
  ULONG(STDMETHODCALLTYPE *Release)(win_hello_done *);
  HRESULT(STDMETHODCALLTYPE *Invoke)(win_hello_done *, IInspectable *, AsyncStatus);
} win_hello_done_vtbl;
struct win_hello_done {
  const win_hello_done_vtbl *lpVtbl;
  volatile LONG refs;
  const IID *iid;
  HANDLE ev;  // the waiter's; set once, never touched after
  volatile LONG status;
};

static HRESULT STDMETHODCALLTYPE win_hello_done_qi(win_hello_done *d, REFIID riid, void **out) {
  if (!out) return E_POINTER;
  if (IsEqualIID(riid, &IID_IUnknown) || IsEqualIID(riid, &WIN_HELLO_IID_AGILE) || IsEqualIID(riid, d->iid)) {
    *out = d;
    InterlockedIncrement(&d->refs);
    return S_OK;
  }
  *out = NULL;
  return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE win_hello_done_add(win_hello_done *d) { return (ULONG)InterlockedIncrement(&d->refs); }

static ULONG STDMETHODCALLTYPE win_hello_done_release(win_hello_done *d) {
  LONG n = InterlockedDecrement(&d->refs);
  if (n == 0) free(d);
  return (ULONG)n;
}

static HRESULT STDMETHODCALLTYPE win_hello_done_invoke(win_hello_done *d, IInspectable *op, AsyncStatus status) {
  (void)op;
  InterlockedExchange(&d->status, (LONG)status);
  SetEvent(d->ev);
  return S_OK;
}

static const win_hello_done_vtbl win_hello_done_vt = {win_hello_done_qi, win_hello_done_add, win_hello_done_release, win_hello_done_invoke};

static win_hello_done *win_hello_done_new(const IID *iid, HANDLE ev) {
  win_hello_done *d = (win_hello_done *)calloc(1, sizeof *d);
  if (!d) return NULL;
  d->lpVtbl = &win_hello_done_vt;
  d->refs = 1;
  d->iid = iid;
  d->ev = ev;
  d->status = Started;
  return d;
}

// The event a completion is waited on, and its handler.
static HRESULT win_hello_waiter(const IID *iid, HANDLE *ev, win_hello_done **done) {
  *ev = CreateEventW(NULL, TRUE, FALSE, NULL);
  if (!*ev) return HRESULT_FROM_WIN32(GetLastError());
  *done = win_hello_done_new(iid, *ev);
  return *done ? S_OK : E_OUTOFMEMORY;
}

// An operation that did not complete: why, as its IAsyncInfo says it (Canceled: the person's, as Hello's own cancel).
static HRESULT win_hello_failed(IUnknown *op, LONG status) {
  if (status == Canceled) return E_ABORT;
  IAsyncInfo *info = NULL;
  HRESULT code = E_FAIL;
  // (through the vtables, not COBJMACROS': unknwn.h and asyncinfo.h may have come before this file, without them)
  if (SUCCEEDED(op->lpVtbl->QueryInterface(op, &WIN_HELLO_IID_ASYNC_INFO, (void **)&info)) && info) {
    if (FAILED(info->lpVtbl->get_ErrorCode(info, &code)) || SUCCEEDED(code)) code = E_FAIL;
    info->lpVtbl->Release(info);
  }
  return code;
}

// WinRT on this thread for as long as it is asked (`*mine`: begun here, so ended here); a thread in an STA already
// goes on as it is (the handlers are agile, called on a pool thread, so waiting here blocks nothing they need).
static HRESULT win_hello_begin(int *mine) {
  HRESULT hr = RoInitialize(RO_INIT_MULTITHREADED);
  *mine = hr == S_OK || hr == S_FALSE;
  return hr == RPC_E_CHANGED_MODE || SUCCEEDED(hr) ? S_OK : hr;
}

static HRESULT win_hello_factory(const IID *iid, void **out) {
  HSTRING_HEADER h;
  HSTRING name = NULL;
  static const WCHAR cls[] = L"Windows.Security.Credentials.UI.UserConsentVerifier";
  HRESULT hr = WindowsCreateStringReference(cls, (UINT32)(sizeof cls / sizeof cls[0] - 1), &h, &name);
  if (SUCCEEDED(hr)) hr = RoGetActivationFactory(name, iid, out);
  return hr;
}

// ── the two questions ──

static const char *win_hello_check(void) {
  int mine = 0;
  HRESULT hr = win_hello_begin(&mine);
  if (FAILED(hr)) return win_hello_hresult_error(hr);
  win_hello_statics *statics = NULL;
  win_hello_avail_op *op = NULL;
  win_hello_done *done = NULL;
  HANDLE ev = NULL;
  const char *why = NULL;
  __x_ABI_CWindows_CSecurity_CCredentials_CUI_CUserConsentVerifierAvailability avail =
      UserConsentVerifierAvailability_DeviceNotPresent;
  hr = win_hello_factory(&WIN_HELLO_IID_STATICS, (void **)&statics);
  if (SUCCEEDED(hr)) hr = __x_ABI_CWindows_CSecurity_CCredentials_CUI_CIUserConsentVerifierStatics_CheckAvailabilityAsync(statics, &op);
  if (SUCCEEDED(hr)) hr = win_hello_waiter(&WIN_HELLO_IID_AVAIL_DONE, &ev, &done);
  if (SUCCEEDED(hr))
    hr = __FIAsyncOperation_1_Windows__CSecurity__CCredentials__CUI__CUserConsentVerifierAvailability_put_Completed(
        op, (__FIAsyncOperationCompletedHandler_1_Windows__CSecurity__CCredentials__CUI__CUserConsentVerifierAvailability *)done);
  if (SUCCEEDED(hr)) {
    WaitForSingleObject(ev, INFINITE);
    LONG status = InterlockedCompareExchange(&done->status, 0, 0);
    if (status == Completed) hr = __FIAsyncOperation_1_Windows__CSecurity__CCredentials__CUI__CUserConsentVerifierAvailability_GetResults(op, &avail);
    else hr = win_hello_failed((IUnknown *)op, status);
  }
  // (no other failure: whatever keeps the question from being asked is no Hello here)
  why = FAILED(hr) ? "no_device_lock" : win_hello_availability_error((int)avail);
  if (done) win_hello_done_release(done);
  if (op) __FIAsyncOperation_1_Windows__CSecurity__CCredentials__CUI__CUserConsentVerifierAvailability_Release(op);
  if (statics) __x_ABI_CWindows_CSecurity_CCredentials_CUI_CIUserConsentVerifierStatics_Release(statics);
  if (ev) CloseHandle(ev);
  if (mine) RoUninitialize();
  return why;
}

static const char *win_hello_ask(HWND window, const char *reason_utf8) {
  // a window shown to ask over (not asked to be in front: the person may be reading a pairing's code in another
  // app's, as the Mac's prompt comes over whatever is in front)
  if (!window || !IsWindow(window) || !IsWindowVisible(window) || IsIconic(window)) return "not_in_front";
  if (!reason_utf8 || !*reason_utf8) {
    // (its product's name: MBUI_PRODUCT, monoid's apps; else still.fail)
    const char *product = getenv("MBUI_PRODUCT");
    reason_utf8 = product && *product ? product : "still.fail";
  }
  int mine = 0;
  HRESULT hr = win_hello_begin(&mine);
  if (FAILED(hr)) return win_hello_hresult_error(hr);
  win_hello_interop *interop = NULL;
  win_hello_result_op *op = NULL;
  win_hello_done *done = NULL;
  HANDLE ev = NULL;
  HSTRING msg = NULL;
  WCHAR *wide = NULL;
  const char *why = NULL;
  __x_ABI_CWindows_CSecurity_CCredentials_CUI_CUserConsentVerificationResult res = UserConsentVerificationResult_Canceled;
  int n = MultiByteToWideChar(CP_UTF8, 0, reason_utf8, -1, NULL, 0);
  if (n > 0) wide = (WCHAR *)malloc((size_t)n * sizeof(WCHAR));
  if (!wide || MultiByteToWideChar(CP_UTF8, 0, reason_utf8, -1, wide, n) <= 0) hr = E_INVALIDARG;
  if (SUCCEEDED(hr)) hr = WindowsCreateString(wide, (UINT32)(n - 1), &msg);
  if (SUCCEEDED(hr)) hr = win_hello_factory(&WIN_HELLO_IID_INTEROP, (void **)&interop);
  if (SUCCEEDED(hr)) hr = interop->lpVtbl->RequestVerificationForWindowAsync(interop, window, msg, &WIN_HELLO_IID_RESULT_OP, (void **)&op);
  if (SUCCEEDED(hr)) hr = win_hello_waiter(&WIN_HELLO_IID_RESULT_DONE, &ev, &done);
  if (SUCCEEDED(hr))
    hr = __FIAsyncOperation_1_Windows__CSecurity__CCredentials__CUI__CUserConsentVerificationResult_put_Completed(
        op, (__FIAsyncOperationCompletedHandler_1_Windows__CSecurity__CCredentials__CUI__CUserConsentVerificationResult *)done);
  if (SUCCEEDED(hr)) {
    WaitForSingleObject(ev, INFINITE);
    LONG status = InterlockedCompareExchange(&done->status, 0, 0);
    if (status == Completed) hr = __FIAsyncOperation_1_Windows__CSecurity__CCredentials__CUI__CUserConsentVerificationResult_GetResults(op, &res);
    else hr = win_hello_failed((IUnknown *)op, status);
  }
  why = FAILED(hr) ? win_hello_hresult_error(hr) : win_hello_result_error((int)res);
  if (done) win_hello_done_release(done);
  if (op) __FIAsyncOperation_1_Windows__CSecurity__CCredentials__CUI__CUserConsentVerificationResult_Release(op);
  if (interop) interop->lpVtbl->Release(interop);
  if (msg) WindowsDeleteString(msg);
  free(wide);
  if (ev) CloseHandle(ev);
  if (mine) RoUninitialize();
  return why;
}

#endif
