#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <mmsystem.h>
#define LBA2_FAKE_MCI_DEVICE 1

extern IMAGE_DOS_HEADER __ImageBase;
static HMODULE real_winmm;

static FARPROC real_proc(const char *name) {
    if (real_winmm == NULL) {
        wchar_t path[MAX_PATH];
        DWORD n = GetModuleFileNameW((HMODULE)&__ImageBase, path, MAX_PATH);
        if (n == 0 || n >= MAX_PATH) {
            return NULL;
        }
        for (DWORD i = n; i > 0; --i) {
            if (path[i - 1] == L'\\' || path[i - 1] == L'/') {
                path[i] = 0;
                break;
            }
        }
        if (lstrlenW(path) + 15 < MAX_PATH) {
            lstrcatW(path, L"winmm_real.dll");
            real_winmm = LoadLibraryW(path);
        }
        if (real_winmm == NULL) {
            UINT sys_len = GetSystemDirectoryW(path, MAX_PATH);
            if (sys_len == 0 || sys_len >= MAX_PATH || lstrlenW(path) + 11 >= MAX_PATH) {
                return NULL;
            }
            lstrcatW(path, L"\\winmm.dll");
            real_winmm = LoadLibraryW(path);
        }
        if (real_winmm == NULL) {
            return NULL;
        }
    }
    return GetProcAddress(real_winmm, name);
}


static void log_mci_call(const char *api, UINT msg, DWORD_PTR params, MCIERROR before, MCIERROR after) {
    char enabled[8];
    if (GetEnvironmentVariableA("LBA2_WINMM_PROXY_LOG", enabled, sizeof(enabled)) == 0) {
        return;
    }

    char line[256];
    DWORD item = 0;
    DWORD ret = 0;
    if (params != 0 && msg == MCI_STATUS) {
        MCI_STATUS_PARMS *status = (MCI_STATUS_PARMS *)params;
        item = status->dwItem;
        ret = (DWORD)status->dwReturn;
    }
    wsprintfA(line, "%s msg=0x%04x item=%lu ret=%lu before=%lu after=%lu\r\n", api, msg, item, ret, before, after);
    HANDLE file = CreateFileA("winmm_proxy.log", FILE_APPEND_DATA, FILE_SHARE_READ, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file != INVALID_HANDLE_VALUE) {
        DWORD written = 0;
        WriteFile(file, line, lstrlenA(line), &written, NULL);
        CloseHandle(file);
    }
}

static void force_mci_ready(DWORD_PTR params, MCIERROR *result) {
    if (params == 0 || result == NULL) {
        return;
    }

    MCI_STATUS_PARMS *status = (MCI_STATUS_PARMS *)params;
    switch (status->dwItem) {
    case MCI_STATUS_MODE:
        status->dwReturn = MCI_MODE_STOP;
        *result = 0;
        break;
    case MCI_STATUS_NUMBER_OF_TRACKS:
        status->dwReturn = 2;
        *result = 0;
        break;
    case MCI_STATUS_MEDIA_PRESENT:
    case MCI_STATUS_READY:
        status->dwReturn = 1;
        *result = 0;
        break;
    default:
        break;
    }
}

MCIERROR WINAPI proxy_mciSendCommandA(MCIDEVICEID id, UINT msg, DWORD_PTR flags, DWORD_PTR params) {
    typedef MCIERROR(WINAPI *Fn)(MCIDEVICEID, UINT, DWORD_PTR, DWORD_PTR);
    Fn fn = (Fn)real_proc("mciSendCommandA");
    MCIERROR result = fn ? fn(id, msg, flags, params) : MMSYSERR_ERROR;
    MCIERROR before = result;
    if (msg == MCI_OPEN && params != 0) {
        ((MCI_OPEN_PARMSA *)params)->wDeviceID = LBA2_FAKE_MCI_DEVICE;
        result = 0;
    } else if (msg == MCI_STATUS) {
        force_mci_ready(params, &result);
    } else if (id == LBA2_FAKE_MCI_DEVICE && (msg == MCI_CLOSE || msg == MCI_SET || msg == MCI_STOP || msg == MCI_PLAY)) {
        result = 0;
    }
    log_mci_call("mciSendCommandA", msg, params, before, result);
    return result;
}

MCIERROR WINAPI proxy_mciSendCommandW(MCIDEVICEID id, UINT msg, DWORD_PTR flags, DWORD_PTR params) {
    typedef MCIERROR(WINAPI *Fn)(MCIDEVICEID, UINT, DWORD_PTR, DWORD_PTR);
    Fn fn = (Fn)real_proc("mciSendCommandW");
    MCIERROR result = fn ? fn(id, msg, flags, params) : MMSYSERR_ERROR;
    MCIERROR before = result;
    if (msg == MCI_OPEN && params != 0) {
        ((MCI_OPEN_PARMSW *)params)->wDeviceID = LBA2_FAKE_MCI_DEVICE;
        result = 0;
    } else if (msg == MCI_STATUS) {
        force_mci_ready(params, &result);
    } else if (id == LBA2_FAKE_MCI_DEVICE && (msg == MCI_CLOSE || msg == MCI_SET || msg == MCI_STOP || msg == MCI_PLAY)) {
        result = 0;
    }
    log_mci_call("mciSendCommandW", msg, params, before, result);
    return result;
}

MCIERROR WINAPI proxy_mciSendStringA(LPCSTR command, LPSTR ret, UINT ret_len, HWND callback) {
    typedef MCIERROR(WINAPI *Fn)(LPCSTR, LPSTR, UINT, HWND);
    Fn fn = (Fn)real_proc("mciSendStringA");
    return fn ? fn(command, ret, ret_len, callback) : MMSYSERR_ERROR;
}

MCIERROR WINAPI proxy_mciSendStringW(LPCWSTR command, LPWSTR ret, UINT ret_len, HWND callback) {
    typedef MCIERROR(WINAPI *Fn)(LPCWSTR, LPWSTR, UINT, HWND);
    Fn fn = (Fn)real_proc("mciSendStringW");
    return fn ? fn(command, ret, ret_len, callback) : MMSYSERR_ERROR;
}

DWORD WINAPI proxy_timeGetTime(void) {
    typedef DWORD(WINAPI *Fn)(void);
    Fn fn = (Fn)real_proc("timeGetTime");
    return fn ? fn() : GetTickCount();
}

UINT WINAPI proxy_joyGetNumDevs(void) {
    typedef UINT(WINAPI *Fn)(void);
    Fn fn = (Fn)real_proc("joyGetNumDevs");
    return fn ? fn() : 0;
}

MMRESULT WINAPI proxy_joyGetDevCapsA(UINT_PTR id, LPJOYCAPSA caps, UINT size) {
    typedef MMRESULT(WINAPI *Fn)(UINT_PTR, LPJOYCAPSA, UINT);
    Fn fn = (Fn)real_proc("joyGetDevCapsA");
    return fn ? fn(id, caps, size) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_joyGetPosEx(UINT id, LPJOYINFOEX info) {
    typedef MMRESULT(WINAPI *Fn)(UINT, LPJOYINFOEX);
    Fn fn = (Fn)real_proc("joyGetPosEx");
    return fn ? fn(id, info) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_mixerOpen(LPHMIXER mixer, UINT id, DWORD_PTR callback, DWORD_PTR instance, DWORD flags) {
    typedef MMRESULT(WINAPI *Fn)(LPHMIXER, UINT, DWORD_PTR, DWORD_PTR, DWORD);
    Fn fn = (Fn)real_proc("mixerOpen");
    return fn ? fn(mixer, id, callback, instance, flags) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_mixerClose(HMIXER mixer) {
    typedef MMRESULT(WINAPI *Fn)(HMIXER);
    Fn fn = (Fn)real_proc("mixerClose");
    return fn ? fn(mixer) : MMSYSERR_NODRIVER;
}

UINT WINAPI proxy_mixerGetNumDevs(void) {
    typedef UINT(WINAPI *Fn)(void);
    Fn fn = (Fn)real_proc("mixerGetNumDevs");
    return fn ? fn() : 0;
}

MMRESULT WINAPI proxy_mixerGetLineInfoA(HMIXEROBJ mixer, LPMIXERLINEA line, DWORD flags) {
    typedef MMRESULT(WINAPI *Fn)(HMIXEROBJ, LPMIXERLINEA, DWORD);
    Fn fn = (Fn)real_proc("mixerGetLineInfoA");
    return fn ? fn(mixer, line, flags) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_mixerGetLineControlsA(HMIXEROBJ mixer, LPMIXERLINECONTROLSA controls, DWORD flags) {
    typedef MMRESULT(WINAPI *Fn)(HMIXEROBJ, LPMIXERLINECONTROLSA, DWORD);
    Fn fn = (Fn)real_proc("mixerGetLineControlsA");
    return fn ? fn(mixer, controls, flags) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_mixerGetControlDetailsA(HMIXEROBJ mixer, LPMIXERCONTROLDETAILS details, DWORD flags) {
    typedef MMRESULT(WINAPI *Fn)(HMIXEROBJ, LPMIXERCONTROLDETAILS, DWORD);
    Fn fn = (Fn)real_proc("mixerGetControlDetailsA");
    return fn ? fn(mixer, details, flags) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_mixerSetControlDetails(HMIXEROBJ mixer, LPMIXERCONTROLDETAILS details, DWORD flags) {
    typedef MMRESULT(WINAPI *Fn)(HMIXEROBJ, LPMIXERCONTROLDETAILS, DWORD);
    Fn fn = (Fn)real_proc("mixerSetControlDetails");
    return fn ? fn(mixer, details, flags) : MMSYSERR_NODRIVER;
}

UINT WINAPI proxy_auxGetNumDevs(void) {
    typedef UINT(WINAPI *Fn)(void);
    Fn fn = (Fn)real_proc("auxGetNumDevs");
    return fn ? fn() : 0;
}

MMRESULT WINAPI proxy_auxGetDevCapsA(UINT_PTR id, LPAUXCAPSA caps, UINT size) {
    typedef MMRESULT(WINAPI *Fn)(UINT_PTR, LPAUXCAPSA, UINT);
    Fn fn = (Fn)real_proc("auxGetDevCapsA");
    return fn ? fn(id, caps, size) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_auxGetVolume(UINT id, LPDWORD volume) {
    typedef MMRESULT(WINAPI *Fn)(UINT, LPDWORD);
    Fn fn = (Fn)real_proc("auxGetVolume");
    return fn ? fn(id, volume) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_auxSetVolume(UINT id, DWORD volume) {
    typedef MMRESULT(WINAPI *Fn)(UINT, DWORD);
    Fn fn = (Fn)real_proc("auxSetVolume");
    return fn ? fn(id, volume) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_midiOutOpen(LPHMIDIOUT out, UINT id, DWORD_PTR callback, DWORD_PTR instance, DWORD flags) {
    typedef MMRESULT(WINAPI *Fn)(LPHMIDIOUT, UINT, DWORD_PTR, DWORD_PTR, DWORD);
    Fn fn = (Fn)real_proc("midiOutOpen");
    return fn ? fn(out, id, callback, instance, flags) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_midiOutClose(HMIDIOUT out) {
    typedef MMRESULT(WINAPI *Fn)(HMIDIOUT);
    Fn fn = (Fn)real_proc("midiOutClose");
    return fn ? fn(out) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_midiOutLongMsg(HMIDIOUT out, LPMIDIHDR hdr, UINT size) {
    typedef MMRESULT(WINAPI *Fn)(HMIDIOUT, LPMIDIHDR, UINT);
    Fn fn = (Fn)real_proc("midiOutLongMsg");
    return fn ? fn(out, hdr, size) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_midiOutPrepareHeader(HMIDIOUT out, LPMIDIHDR hdr, UINT size) {
    typedef MMRESULT(WINAPI *Fn)(HMIDIOUT, LPMIDIHDR, UINT);
    Fn fn = (Fn)real_proc("midiOutPrepareHeader");
    return fn ? fn(out, hdr, size) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_midiOutReset(HMIDIOUT out) {
    typedef MMRESULT(WINAPI *Fn)(HMIDIOUT);
    Fn fn = (Fn)real_proc("midiOutReset");
    return fn ? fn(out) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_midiOutShortMsg(HMIDIOUT out, DWORD msg) {
    typedef MMRESULT(WINAPI *Fn)(HMIDIOUT, DWORD);
    Fn fn = (Fn)real_proc("midiOutShortMsg");
    return fn ? fn(out, msg) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_midiOutUnprepareHeader(HMIDIOUT out, LPMIDIHDR hdr, UINT size) {
    typedef MMRESULT(WINAPI *Fn)(HMIDIOUT, LPMIDIHDR, UINT);
    Fn fn = (Fn)real_proc("midiOutUnprepareHeader");
    return fn ? fn(out, hdr, size) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_waveOutOpen(LPHWAVEOUT out, UINT id, LPCWAVEFORMATEX fmt, DWORD_PTR callback, DWORD_PTR instance, DWORD flags) {
    typedef MMRESULT(WINAPI *Fn)(LPHWAVEOUT, UINT, LPCWAVEFORMATEX, DWORD_PTR, DWORD_PTR, DWORD);
    Fn fn = (Fn)real_proc("waveOutOpen");
    return fn ? fn(out, id, fmt, callback, instance, flags) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_waveOutClose(HWAVEOUT out) {
    typedef MMRESULT(WINAPI *Fn)(HWAVEOUT);
    Fn fn = (Fn)real_proc("waveOutClose");
    return fn ? fn(out) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_waveOutGetDevCapsA(UINT_PTR id, LPWAVEOUTCAPSA caps, UINT size) {
    typedef MMRESULT(WINAPI *Fn)(UINT_PTR, LPWAVEOUTCAPSA, UINT);
    Fn fn = (Fn)real_proc("waveOutGetDevCapsA");
    return fn ? fn(id, caps, size) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_waveOutGetID(HWAVEOUT out, LPUINT id) {
    typedef MMRESULT(WINAPI *Fn)(HWAVEOUT, LPUINT);
    Fn fn = (Fn)real_proc("waveOutGetID");
    return fn ? fn(out, id) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_waveOutPrepareHeader(HWAVEOUT out, LPWAVEHDR hdr, UINT size) {
    typedef MMRESULT(WINAPI *Fn)(HWAVEOUT, LPWAVEHDR, UINT);
    Fn fn = (Fn)real_proc("waveOutPrepareHeader");
    return fn ? fn(out, hdr, size) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_waveOutReset(HWAVEOUT out) {
    typedef MMRESULT(WINAPI *Fn)(HWAVEOUT);
    Fn fn = (Fn)real_proc("waveOutReset");
    return fn ? fn(out) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_waveOutSetVolume(HWAVEOUT out, DWORD volume) {
    typedef MMRESULT(WINAPI *Fn)(HWAVEOUT, DWORD);
    Fn fn = (Fn)real_proc("waveOutSetVolume");
    return fn ? fn(out, volume) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_waveOutUnprepareHeader(HWAVEOUT out, LPWAVEHDR hdr, UINT size) {
    typedef MMRESULT(WINAPI *Fn)(HWAVEOUT, LPWAVEHDR, UINT);
    Fn fn = (Fn)real_proc("waveOutUnprepareHeader");
    return fn ? fn(out, hdr, size) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_waveOutWrite(HWAVEOUT out, LPWAVEHDR hdr, UINT size) {
    typedef MMRESULT(WINAPI *Fn)(HWAVEOUT, LPWAVEHDR, UINT);
    Fn fn = (Fn)real_proc("waveOutWrite");
    return fn ? fn(out, hdr, size) : MMSYSERR_NODRIVER;
}

MMRESULT WINAPI proxy_timeBeginPeriod(UINT period) {
    typedef MMRESULT(WINAPI *Fn)(UINT);
    Fn fn = (Fn)real_proc("timeBeginPeriod");
    return fn ? fn(period) : MMSYSERR_NOERROR;
}

MMRESULT WINAPI proxy_timeEndPeriod(UINT period) {
    typedef MMRESULT(WINAPI *Fn)(UINT);
    Fn fn = (Fn)real_proc("timeEndPeriod");
    return fn ? fn(period) : MMSYSERR_NOERROR;
}

MMRESULT WINAPI proxy_timeKillEvent(UINT timer_id) {
    typedef MMRESULT(WINAPI *Fn)(UINT);
    Fn fn = (Fn)real_proc("timeKillEvent");
    return fn ? fn(timer_id) : MMSYSERR_NOERROR;
}

MMRESULT WINAPI proxy_timeSetEvent(UINT delay, UINT resolution, LPTIMECALLBACK callback, DWORD_PTR user, UINT event) {
    typedef MMRESULT(WINAPI *Fn)(UINT, UINT, LPTIMECALLBACK, DWORD_PTR, UINT);
    Fn fn = (Fn)real_proc("timeSetEvent");
    return fn ? fn(delay, resolution, callback, user, event) : 0;
}
BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    (void)instance;
    (void)reserved;
    if (reason == DLL_PROCESS_DETACH && real_winmm != NULL) {
        FreeLibrary(real_winmm);
        real_winmm = NULL;
    }
    return TRUE;
}







