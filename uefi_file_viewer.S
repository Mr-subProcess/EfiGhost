.intel_syntax noprefix

/*
 * UEFI x86-64 local file viewer.
 * Microsoft x64 ABI; PE/COFF is produced by clang + lld-link.
 * Reads at most 256 bytes from \veri.txt on the EFI System Partition
 * and displays an ASCII-safe rendering on the UEFI console.
 * No network, persistence, background loop, or arbitrary script execution.
 */

.equ EFI_SUCCESS,       0
.equ EFI_LOAD_ERROR,    0x8000000000000001
.equ EFI_INVALID_PARAMETER, 0x8000000000000002
.equ EFI_UNSUPPORTED,   0x8000000000000003
.equ EFI_DEVICE_ERROR,  0x8000000000000007
.equ EFI_NOT_FOUND,     0x800000000000000e
.equ EFI_ABORTED,       0x8000000000000015

.equ ST_CON_OUT,        0x40
.equ ST_BOOT_SERVICES,  0x60
.equ BS_LOCATE_PROTOCOL,0x140
.equ SFS_OPEN_VOLUME,   0x08
.equ FILE_OPEN,         0x08
.equ FILE_CLOSE,        0x10
.equ FILE_READ,         0x20
.equ EFI_FILE_MODE_READ,1
.equ MAX_READ,          256

.section .text,"xr"
.p2align 4
.globl efi_main
.def efi_main; .scl 2; .type 32; .endef

/* EFI_STATUS EFIAPI efi_main(EFI_HANDLE ImageHandle,
 *                            EFI_SYSTEM_TABLE *SystemTable)
 * RCX = ImageHandle, RDX = SystemTable.
 */
efi_main:
    /* Entry RSP is 8 mod 16. Reserve shadow space + one stack argument. */
    sub     rsp, 40

    mov     qword ptr [rip + g_exit_status], EFI_SUCCESS
    test    rdx, rdx
    jz      .bad_system_table

    mov     rax, qword ptr [rdx + ST_CON_OUT]
    mov     qword ptr [rip + g_con_out], rax
    mov     rax, qword ptr [rdx + ST_BOOT_SERVICES]
    mov     qword ptr [rip + g_boot_services], rax
    test    rax, rax
    jz      .bad_system_table

    /* Absolute image pointer below deliberately exercises PE base relocations. */
    mov     rdx, qword ptr [rip + g_msg_banner_ptr]
    call    print_str

    /* LocateProtocol(EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID, NULL, &Sfs). */
    mov     rax, qword ptr [rip + g_boot_services]
    mov     rax, qword ptr [rax + BS_LOCATE_PROTOCOL]
    test    rax, rax
    jz      .unsupported
    lea     rcx, [rip + guid_sfs]
    xor     edx, edx
    lea     r8,  [rip + g_sfs]
    call    rax
    test    rax, rax
    jnz     .filesystem_missing

    /* Sfs->OpenVolume(Sfs, &Root). */
    mov     rcx, qword ptr [rip + g_sfs]
    test    rcx, rcx
    jz      .filesystem_missing
    mov     rax, qword ptr [rcx + SFS_OPEN_VOLUME]
    test    rax, rax
    jz      .unsupported
    lea     rdx, [rip + g_root]
    call    rax
    test    rax, rax
    jnz     .io_error

    /* Root->Open(Root, &File, L"veri.txt", READ, 0). */
    mov     rcx, qword ptr [rip + g_root]
    test    rcx, rcx
    jz      .io_error
    mov     rax, qword ptr [rcx + FILE_OPEN]
    test    rax, rax
    jz      .unsupported
    lea     rdx, [rip + g_file]
    lea     r8,  [rip + filename]
    mov     r9, EFI_FILE_MODE_READ
    mov     qword ptr [rsp + 32], 0
    call    rax
    test    rax, rax
    jnz     .file_missing

    /* File->Read(File, &Size, Buffer), with a hard 256-byte bound. */
    mov     qword ptr [rip + g_read_size], MAX_READ
    mov     rcx, qword ptr [rip + g_file]
    test    rcx, rcx
    jz      .io_error
    mov     rax, qword ptr [rcx + FILE_READ]
    test    rax, rax
    jz      .unsupported
    lea     rdx, [rip + g_read_size]
    lea     r8,  [rip + g_ascii_buf]
    call    rax
    test    rax, rax
    jnz     .io_error

    mov     r9, qword ptr [rip + g_read_size]
    cmp     r9, MAX_READ
    ja      .bad_read_size
    test    r9, r9
    jz      .empty_file

    /* Convert bounded ASCII bytes to NUL-terminated CHAR16.
       Non-printable/non-ASCII bytes become '?'; CR/LF/TAB are preserved. */
    lea     r10, [rip + g_ascii_buf]
    lea     r11, [rip + g_utf16_buf]
    xor     r8d, r8d
.convert_loop:
    cmp     r8, r9
    jae     .convert_done
    movzx   eax, byte ptr [r10 + r8]
    cmp     eax, 0x20
    jae     .check_upper_ascii
    cmp     eax, 0x09
    je      .store_char
    cmp     eax, 0x0a
    je      .store_char
    cmp     eax, 0x0d
    je      .store_char
    mov     eax, '?'
    jmp     .store_char
.check_upper_ascii:
    cmp     eax, 0x7e
    jbe     .store_char
    mov     eax, '?'
.store_char:
    mov     word ptr [r11 + r8*2], ax
    inc     r8
    jmp     .convert_loop
.convert_done:
    mov     word ptr [r11 + r9*2], 0

    lea     rdx, [rip + msg_file_read]
    call    print_str
    lea     rdx, [rip + g_utf16_buf]
    call    print_str
    lea     rdx, [rip + msg_newline]
    call    print_str

    cmp     qword ptr [rip + g_read_size], MAX_READ
    jne     .success_cleanup
    lea     rdx, [rip + msg_truncated]
    call    print_str

.success_cleanup:
    call    close_handles
    mov     qword ptr [rip + g_exit_status], EFI_SUCCESS
    jmp     .return_status

.bad_system_table:
    mov     rax, EFI_INVALID_PARAMETER
    mov     qword ptr [rip + g_exit_status], rax
    lea     rdx, [rip + msg_bad_system_table]
    call    print_str
    jmp     .return_status

.unsupported:
    mov     rax, EFI_UNSUPPORTED
    mov     qword ptr [rip + g_exit_status], rax
    lea     rdx, [rip + msg_unsupported]
    call    print_str
    call    close_handles
    jmp     .return_status

.filesystem_missing:
    mov     rax, EFI_NOT_FOUND
    mov     qword ptr [rip + g_exit_status], rax
    lea     rdx, [rip + msg_no_fs]
    call    print_str
    call    close_handles
    jmp     .return_status

.file_missing:
    mov     rax, EFI_NOT_FOUND
    mov     qword ptr [rip + g_exit_status], rax
    lea     rdx, [rip + msg_no_file]
    call    print_str
    call    close_handles
    jmp     .return_status

.empty_file:
    mov     qword ptr [rip + g_exit_status], EFI_SUCCESS
    lea     rdx, [rip + msg_empty]
    call    print_str
    call    close_handles
    jmp     .return_status

.bad_read_size:
.io_error:
    mov     rax, EFI_DEVICE_ERROR
    mov     qword ptr [rip + g_exit_status], rax
    lea     rdx, [rip + msg_read_error]
    call    print_str
    call    close_handles

.return_status:
    mov     rax, qword ptr [rip + g_exit_status]
    add     rsp, 40
    ret

/* print_str(RDX = CHAR16*).  Preserves all nonvolatile registers. */
.p2align 4
print_str:
    sub     rsp, 40
    mov     rax, qword ptr [rip + g_con_out]
    test    rax, rax
    jz      .print_done
    mov     rcx, rax
    call    qword ptr [rax + 0x08]   /* EFI_SIMPLE_TEXT_OUTPUT_PROTOCOL.OutputString */
.print_done:
    add     rsp, 40
    ret

/* Close file/root handles if open. */
.p2align 4
close_handles:
    sub     rsp, 40
    mov     rcx, qword ptr [rip + g_file]
    test    rcx, rcx
    jz      .close_root
    mov     rax, qword ptr [rcx + FILE_CLOSE]
    test    rax, rax
    jz      .clear_file
    call    rax
.clear_file:
    mov     qword ptr [rip + g_file], 0
.close_root:
    mov     rcx, qword ptr [rip + g_root]
    test    rcx, rcx
    jz      .close_done
    mov     rax, qword ptr [rcx + FILE_CLOSE]
    test    rax, rax
    jz      .clear_root
    call    rax
.clear_root:
    mov     qword ptr [rip + g_root], 0
.close_done:
    add     rsp, 40
    ret

.section .rdata,"dr"
.p2align 4
guid_sfs:
    /* EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID: 964E5B22-6459-11D2-8E39-00A0C969723B */
    .byte 0x22,0x5b,0x4e,0x96,0x59,0x64,0xd2,0x11
    .byte 0x8e,0x39,0x00,0xa0,0xc9,0x69,0x72,0x3b
filename:
    .short 'v','e','r','i','.','t','x','t',0
msg_banner:
    .short 'U','E','F','I',' ','L','o','c','a','l',' ','F','i','l','e',' ','V','i','e','w','e','r',':',0x0d,0x0a,0
msg_file_read:
    .short 0x0d,0x0a,'D','o','s','y','a',' ','i','c','e','r','i','g','i',':',0x0d,0x0a,0
msg_newline:
    .short 0x0d,0x0a,0
msg_truncated:
    .short '[','N','o','t',':',' ','i','l','k',' ','2','5','6',' ','b','a','y','t',' ','g','o','s','t','e','r','i','l','d','i',']',0x0d,0x0a,0
msg_bad_system_table:
    .short 'H','a','t','a',':',' ','S','y','s','t','e','m','T','a','b','l','e',0x0d,0x0a,0
msg_unsupported:
    .short 'H','a','t','a',':',' ','G','e','r','e','k','l','i',' ','U','E','F','I',' ','p','r','o','t','o','k','o','l','u',' ','y','o','k',0x0d,0x0a,0
msg_no_fs:
    .short 'H','a','t','a',':',' ','S','i','m','p','l','e','F','i','l','e','S','y','s','t','e','m',' ','b','u','l','u','n','a','m','a','d','i',0x0d,0x0a,0
msg_no_file:
    .short 'H','a','t','a',':',' ','v','e','r','i','.','t','x','t',' ','b','u','l','u','n','a','m','a','d','i',0x0d,0x0a,0
msg_empty:
    .short 'D','o','s','y','a',' ','b','o','s',0x0d,0x0a,0
msg_read_error:
    .short 'H','a','t','a',':',' ','D','o','s','y','a',' ','o','k','u','m','a',' ','i','s','l','e','m','i',' ','b','a','s','a','r','i','s','i','z',0x0d,0x0a,0

.section .data,"dw"
.p2align 3
g_boot_services: .quad 0
g_con_out:       .quad 0
g_sfs:           .quad 0
g_root:          .quad 0
g_file:          .quad 0
g_read_size:     .quad 0
g_exit_status:   .quad 0
g_msg_banner_ptr: .quad msg_banner

.section .bss,"bw"
.p2align 4
g_ascii_buf:     .zero MAX_READ
g_utf16_buf:     .zero (MAX_READ + 1) * 2
.intel_syntax noprefix

/*
 * UEFI x86-64 local file viewer + continuous HTTP POST.
 * Microsoft x64 ABI; PE/COFF is produced by clang + lld-link.
 * Reads at most 256 bytes from \veri.txt on the EFI System Partition,
 * displays an ASCII-safe rendering, then enters an infinite loop that
 * re-reads the file and sends its contents via HTTP POST.
 */

.equ EFI_SUCCESS,           0
.equ EFI_LOAD_ERROR,        0x8000000000000001
.equ EFI_INVALID_PARAMETER, 0x8000000000000002
.equ EFI_UNSUPPORTED,       0x8000000000000003
.equ EFI_DEVICE_ERROR,      0x8000000000000007
.equ EFI_NOT_FOUND,         0x800000000000000e
.equ EFI_ABORTED,           0x8000000000000015

.equ ST_CON_OUT,            0x40
.equ ST_BOOT_SERVICES,      0x60

/* EFI_BOOT_SERVICES offsets (64-bit, header 0x18 + 8-byte entries) */
.equ BS_CREATE_EVENT,       0x50
.equ BS_WAIT_FOR_EVENT,     0x60
.equ BS_CLOSE_EVENT,        0x70
.equ BS_LOCATE_PROTOCOL,    0x140
.equ BS_STALL,              0xF8
.equ BS_SET_WATCHDOG,       0x100

/* EFI_SIMPLE_FILE_SYSTEM_PROTOCOL */
.equ SFS_OPEN_VOLUME,       0x08
/* EFI_FILE_PROTOCOL */
.equ FILE_OPEN,             0x08
.equ FILE_CLOSE,            0x10
.equ FILE_READ,             0x20
.equ FILE_SET_POSITION,     0x38

.equ EFI_FILE_MODE_READ,    1
.equ MAX_READ,              256

/* EFI_HTTP_PROTOCOL offsets */
.equ HTTP_GET_MODE_DATA,    0x00
.equ HTTP_CONFIGURE,        0x08
.equ HTTP_REQUEST,          0x10

/* EFI_HTTP_METHOD */
.equ HTTP_METHOD_GET,       0
.equ HTTP_METHOD_POST,      1

/* Event types */
.equ EVT_NOTIFY_SIGNAL,     0x00000200
.equ TPL_CALLBACK,          8

.section .text,"xr"
.p2align 4
.globl efi_main
.def efi_main; .scl 2; .type 32; .endef

efi_main:
    sub     rsp, 40

    mov     qword ptr [rip + g_exit_status], EFI_SUCCESS
    test    rdx, rdx
    jz      .bad_system_table

    mov     rax, qword ptr [rdx + ST_CON_OUT]
    mov     qword ptr [rip + g_con_out], rax
    mov     rax, qword ptr [rdx + ST_BOOT_SERVICES]
    mov     qword ptr [rip + g_boot_services], rax
    test    rax, rax
    jz      .bad_system_table

    /* Disable watchdog timer (otherwise system resets after 5 minutes). */
    mov     rax, qword ptr [rip + g_boot_services]
    mov     rax, qword ptr [rax + BS_SET_WATCHDOG]
    test    rax, rax
    jz      .no_watchdog
    xor     ecx, ecx                /* Timeout = 0 (disable) */
    xor     edx, edx                /* WatchdogCode = 0 */
    xor     r8d, r8d                /* DataSize = 0 */
    xor     r9d, r9d                /* WatchdogData = NULL */
    call    rax
.no_watchdog:

    mov     rdx, qword ptr [rip + g_msg_banner_ptr]
    call    print_str

    /* LocateProtocol(EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID, NULL, &Sfs). */
    mov     rax, qword ptr [rip + g_boot_services]
    mov     rax, qword ptr [rax + BS_LOCATE_PROTOCOL]
    test    rax, rax
    jz      .unsupported
    lea     rcx, [rip + guid_sfs]
    xor     edx, edx
    lea     r8,  [rip + g_sfs]
    call    rax
    test    rax, rax
    jnz     .filesystem_missing

    /* Sfs->OpenVolume(Sfs, &Root). */
    mov     rcx, qword ptr [rip + g_sfs]
    test    rcx, rcx
    jz      .filesystem_missing
    mov     rax, qword ptr [rcx + SFS_OPEN_VOLUME]
    test    rax, rax
    jz      .unsupported
    lea     rdx, [rip + g_root]
    call    rax
    test    rax, rax
    jnz     .io_error

    /* Root->Open(Root, &File, L"veri.txt", READ, 0). */
    mov     rcx, qword ptr [rip + g_root]
    test    rcx, rcx
    jz      .io_error
    mov     rax, qword ptr [rcx + FILE_OPEN]
    test    rax, rax
    jz      .unsupported
    lea     rdx, [rip + g_file]
    lea     r8,  [rip + filename]
    mov     r9, EFI_FILE_MODE_READ
    mov     qword ptr [rsp + 32], 0
    call    rax
    test    rax, rax
    jnz     .file_missing

    /* --- Initial read + display (same as before) --- */
    mov     qword ptr [rip + g_read_size], MAX_READ
    mov     rcx, qword ptr [rip + g_file]
    test    rcx, rcx
    jz      .io_error
    mov     rax, qword ptr [rcx + FILE_READ]
    test    rax, rax
    jz      .unsupported
    lea     rdx, [rip + g_read_size]
    lea     r8,  [rip + g_ascii_buf]
    call    rax
    test    rax, rax
    jnz     .io_error

    mov     r9, qword ptr [rip + g_read_size]
    cmp     r9, MAX_READ
    ja      .bad_read_size
    test    r9, r9
    jz      .empty_file

    lea     r10, [rip + g_ascii_buf]
    lea     r11, [rip + g_utf16_buf]
    xor     r8d, r8d
.convert_loop:
    cmp     r8, r9
    jae     .convert_done
    movzx   eax, byte ptr [r10 + r8]
    cmp     eax, 0x20
    jae     .check_upper_ascii
    cmp     eax, 0x09
    je      .store_char
    cmp     eax, 0x0a
    je      .store_char
    cmp     eax, 0x0d
    je      .store_char
    mov     eax, '?'
    jmp     .store_char
.check_upper_ascii:
    cmp     eax, 0x7e
    jbe     .store_char
    mov     eax, '?'
.store_char:
    mov     word ptr [r11 + r8*2], ax
    inc     r8
    jmp     .convert_loop
.convert_done:
    mov     word ptr [r11 + r9*2], 0

    lea     rdx, [rip + msg_file_read]
    call    print_str
    lea     rdx, [rip + g_utf16_buf]
    call    print_str
    lea     rdx, [rip + msg_newline]
    call    print_str

    cmp     qword ptr [rip + g_read_size], MAX_READ
    jne     .success_cleanup
    lea     rdx, [rip + msg_truncated]
    call    print_str

.success_cleanup:
    /* Keep file handle open for the POST loop. Close only root handle later. */
    mov     qword ptr [rip + g_exit_status], EFI_SUCCESS
    /* Fall through to POST loop instead of returning. */
    jmp     .post_setup

/* ============================================================
 * POST CONFIGURATION: locate HTTP protocol and configure it.
 * ============================================================ */
.post_setup:
    lea     rdx, [rip + msg_http_setup]
    call    print_str

    /* LocateProtocol(EFI_HTTP_PROTOCOL_GUID, NULL, &Http). */
    mov     rax, qword ptr [rip + g_boot_services]
    mov     rax, qword ptr [rax + BS_LOCATE_PROTOCOL]
    test    rax, rax
    jz      .http_missing
    lea     rcx, [rip + guid_http]
    xor     edx, edx
    lea     r8,  [rip + g_http]
    call    rax
    test    rax, rax
    jnz     .http_missing

    /* Http->Configure(Http, &http_config). */
    lea     rax, [rip + http_config]
    mov     rcx, qword ptr [rip + g_http]
    mov     rdx, rax
    mov     rax, qword ptr [rcx + HTTP_CONFIGURE]
    test    rax, rax
    jz      .http_config_fail
    call    rax
    test    rax, rax
    jnz     .http_config_fail

    lea     rdx, [rip + msg_http_ok]
    call    print_str

/* ============================================================
 * POST LOOP: re-read file and send HTTP POST forever.
 * ============================================================ */
.post_loop:
    /* 1) File->SetPosition(File, 0) */
    mov     rcx, qword ptr [rip + g_file]
    test    rcx, rcx
    jz      .post_cleanup
    mov     rax, qword ptr [rcx + FILE_SET_POSITION]
    test    rax, rax
    jz      .post_skip
    xor     edx, edx                /* Position = 0 */
    call    rax
    test    rax, rax
    jnz     .post_skip

    /* 2) File->Read(File, &read_size, ascii_buf) */
    mov     qword ptr [rip + g_read_size], MAX_READ
    mov     rcx, qword ptr [rip + g_file]
    mov     rax, qword ptr [rcx + FILE_READ]
    test    rax, rax
    jz      .post_skip
    lea     rdx, [rip + g_read_size]
    lea     r8,  [rip + g_ascii_buf]
    call    rax
    test    rax, rax
    jnz     .post_skip

    mov     r9, qword ptr [rip + g_read_size]
    test    r9, r9
    jz      .post_skip

    /* 3) CreateEvent(EVT_NOTIFY_SIGNAL, TPL_CALLBACK, NULL, NULL, &Event). */
    mov     rax, qword ptr [rip + g_boot_services]
    mov     rax, qword ptr [rax + BS_CREATE_EVENT]
    test    rax, rax
    jz      .post_skip
    mov     rcx, EVT_NOTIFY_SIGNAL
    mov     rdx, TPL_CALLBACK
    xor     r8d, r8d
    xor     r9d, r9d
    lea     r10, [rip + g_http_event]
    mov     qword ptr [rsp + 32], r10
    call    rax
    test    rax, rax
    jnz     .post_skip

    /* 4) Fill EFI_HTTP_REQUEST_DATA. */
    lea     rax, [rip + g_http_request_data]
    mov     dword ptr [rax], HTTP_METHOD_POST
    lea     rcx, [rip + hedef_url]
    mov     qword ptr [rax + 8], rcx

    /* 5) Fill EFI_HTTP_MESSAGE. */
    lea     rax, [rip + g_http_message]
    lea     rcx, [rip + g_http_request_data]
    mov     qword ptr [rax], rcx          /* Data.Request */
    mov     qword ptr [rax + 8], 0        /* HeaderCount */
    mov     qword ptr [rax + 16], 0       /* Headers */
    mov     rcx, qword ptr [rip + g_read_size]
    mov     qword ptr [rax + 24], rcx     /* BodyLength */
    lea     rcx, [rip + g_ascii_buf]
    mov     qword ptr [rax + 32], rcx     /* Body */

    /* 6) Fill EFI_HTTP_TOKEN. */
    lea     rax, [rip + g_http_token]
    mov     rcx, qword ptr [rip + g_http_event]
    mov     qword ptr [rax], rcx          /* Event */
    mov     qword ptr [rax + 8], 0        /* Status */
    lea     rcx, [rip + g_http_message]
    mov     qword ptr [rax + 16], rcx     /* Message */

    /* 7) Http->Request(Http, &token). */
    mov     rcx, qword ptr [rip + g_http]
    lea     rdx, [rip + g_http_token]
    mov     rax, qword ptr [rcx + HTTP_REQUEST]
    test    rax, rax
    jz      .post_close_event
    call    rax
    test    rax, rax
    jnz     .post_close_event

    /* 8) WaitForEvent(1, &Event, &Index). */
    mov     rax, qword ptr [rip + g_boot_services]
    mov     rax, qword ptr [rax + BS_WAIT_FOR_EVENT]
    test    rax, rax
    jz      .post_close_event
    mov     rcx, 1
    lea     rdx, [rip + g_http_event]
    lea     r8,  [rip + g_event_index]
    call    rax
    test    rax, rax
    jnz     .post_close_event

    /* 9) Check token.Status. */
    lea     rax, [rip + g_http_token]
    mov     rcx, qword ptr [rax + 8]
    test    rcx, rcx
    jnz     .post_status_err

    /* Success: print a dot. */
    lea     rdx, [rip + msg_post_ok]
    call    print_str
    jmp     .post_close_event

.post_status_err:
    lea     rdx, [rip + msg_post_err]
    call    print_str

.post_close_event:
    /* CloseEvent(&Event). */
    mov     rax, qword ptr [rip + g_boot_services]
    mov     rax, qword ptr [rax + BS_CLOSE_EVENT]
    test    rax, rax
    jz      .post_stall
    mov     rcx, qword ptr [rip + g_http_event]
    test    rcx, rcx
    jz      .post_stall
    call    rax

.post_stall:
    /* Stall(1000000 µs = 1 second). */
    mov     rax, qword ptr [rip + g_boot_services]
    mov     rax, qword ptr [rax + BS_STALL]
    test    rax, rax
    jz      .post_loop
    mov     rcx, 1000000
    call    rax
    jmp     .post_loop

.post_skip:
    /* Short stall before retrying on error. */
    mov     rax, qword ptr [rip + g_boot_services]
    mov     rax, qword ptr [rax + BS_STALL]
    test    rax, rax
    jz      .post_loop
    mov     rcx, 1000000
    call    rax
    jmp     .post_loop

.post_cleanup:
    call    close_handles
    jmp     .return_status

/* ============================================================
 * Error paths (mostly unchanged, with POST-related additions).
 * ============================================================ */
.http_missing:
    mov     rax, EFI_UNSUPPORTED
    mov     qword ptr [rip + g_exit_status], rax
    lea     rdx, [rip + msg_http_missing]
    call    print_str
    jmp     .post_cleanup

.http_config_fail:
    mov     rax, EFI_DEVICE_ERROR
    mov     qword ptr [rip + g_exit_status], rax
    lea     rdx, [rip + msg_http_config_fail]
    call    print_str
    jmp     .post_cleanup

.bad_system_table:
    mov     rax, EFI_INVALID_PARAMETER
    mov     qword ptr [rip + g_exit_status], rax
    lea     rdx, [rip + msg_bad_system_table]
    call    print_str
    jmp     .return_status

.unsupported:
    mov     rax, EFI_UNSUPPORTED
    mov     qword ptr [rip + g_exit_status], rax
    lea     rdx, [rip + msg_unsupported]
    call    print_str
    call    close_handles
    jmp     .return_status

.filesystem_missing:
    mov     rax, EFI_NOT_FOUND
    mov     qword ptr [rip + g_exit_status], rax
    lea     rdx, [rip + msg_no_fs]
    call    print_str
    call    close_handles
    jmp     .return_status

.file_missing:
    mov     rax, EFI_NOT_FOUND
    mov     qword ptr [rip + g_exit_status], rax
    lea     rdx, [rip + msg_no_file]
    call    print_str
    call    close_handles
    jmp     .return_status

.empty_file:
    mov     qword ptr [rip + g_exit_status], EFI_SUCCESS
    lea     rdx, [rip + msg_empty]
    call    print_str
    call    close_handles
    jmp     .return_status

.bad_read_size:
.io_error:
    mov     rax, EFI_DEVICE_ERROR
    mov     qword ptr [rip + g_exit_status], rax
    lea     rdx, [rip + msg_read_error]
    call    print_str
    call    close_handles

.return_status:
    mov     rax, qword ptr [rip + g_exit_status]
    add     rsp, 40
    ret

/* print_str(RDX = CHAR16*). Preserves all nonvolatile registers. */
.p2align 4
print_str:
    sub     rsp, 40
    mov     rax, qword ptr [rip + g_con_out]
    test    rax, rax
    jz      .print_done
    mov     rcx, rax
    call    qword ptr [rax + 0x08]
.print_done:
    add     rsp, 40
    ret

/* Close file/root handles if open. */
.p2align 4
close_handles:
    sub     rsp, 40
    mov     rcx, qword ptr [rip + g_file]
    test    rcx, rcx
    jz      .close_root
    mov     rax, qword ptr [rcx + FILE_CLOSE]
    test    rax, rax
    jz      .clear_file
    call    rax
.clear_file:
    mov     qword ptr [rip + g_file], 0
.close_root:
    mov     rcx, qword ptr [rip + g_root]
    test    rcx, rcx
    jz      .close_done
    mov     rax, qword ptr [rcx + FILE_CLOSE]
    test    rax, rax
    jz      .clear_root
    call    rax
.clear_root:
    mov     qword ptr [rip + g_root], 0
.close_done:
    add     rsp, 40
    ret

/* ============================================================
 * Read-only data.
 * ============================================================ */
.section .rdata,"dr"
.p2align 4
guid_sfs:
    /* EFI_SIMPLE_FILE_SYSTEM_PROTOCOL_GUID: 964E5B22-6459-11D2-8E39-00A0C969723B */
    .byte 0x22,0x5b,0x4e,0x96,0x59,0x64,0xd2,0x11
    .byte 0x8e,0x39,0x00,0xa0,0xc9,0x69,0x72,0x3b

/* EFI_HTTP_PROTOCOL_GUID: 7A59B29B-910B-4171-8242-A85A0DF25B5B */
guid_http:
    .byte 0x9b,0xb2,0x59,0x7a,0x0b,0x91,0x71,0x41
    .byte 0x82,0x42,0xa8,0x5a,0x0d,0xf2,0x5b,0x5b

filename:
    .short 'v','e','r','i','.','t','x','t',0

/* Target URL (UTF-16LE). Change to your server address. */
hedef_url:
    .short 'h','t','t','p',':','/','/','1','9','2','.','1','6','8','.','1','.','1','0','0',':','8','0','8','0','/','a','p','i',0

msg_banner:
    .short 'U','E','F','I',' ','L','o','c','a','l',' ','F','i','l','e',' ','V','i','e','w','e','r',':',0x0d,0x0a,0
msg_file_read:
    .short 0x0d,0x0a,'D','o','s','y','a',' ','i','c','e','r','i','g','i',':',0x0d,0x0a,0
msg_newline:
    .short 0x0d,0x0a,0
msg_truncated:
    .short '[','N','o','t',':',' ','i','l','k',' ','2','5','6',' ','b','a','y','t',' ','g','o','s','t','e','r','i','l','d','i',']',0x0d,0x0a,0
msg_bad_system_table:
    .short 'H','a','t','a',':',' ','S','y','s','t','e','m','T','a','b','l','e',0x0d,0x0a,0
msg_unsupported:
    .short 'H','a','t','a',':',' ','G','e','r','e','k','l','i',' ','U','E','F','I',' ','p','r','o','t','o','k','o','l','u',' ','y','o','k',0x0d,0x0a,0
msg_no_fs:
    .short 'H','a','t','a',':',' ','S','i','m','p','l','e','F','i','l','e','S','y','s','t','e','m',' ','b','u','l','u','n','a','m','a','d','i',0x0d,0x0a,0
msg_no_file:
    .short 'H','a','t','a',':',' ','v','e','r','i','.','t','x','t',' ','b','u','l','u','n','a','m','a','d','i',0x0d,0x0a,0
msg_empty:
    .short 'D','o','s','y','a',' ','b','o','s',0x0d,0x0a,0
msg_read_error:
    .short 'H','a','t','a',':',' ','D','o','s','y','a',' ','o','k','u','m','a',' ','i','s','l','e','m','i',' ','b','a','s','a','r','i','s','i','z',0x0d,0x0a,0

/* --- New POST-related messages --- */
msg_http_setup:
    .short 0x0d,0x0a,'H','T','T','P',' ','P','O','S','T',' ','h','a','z','i','r','l','a','n','i','y','o','r','.','.','.',0x0d,0x0a,0
msg_http_ok:
    .short 'H','T','T','P',' ','y','a','p','i','l','a','n','d','i','r','i','l','d','i','.',' ','S','o','n','s','u','z',' ','d','o','n','g','u',' ','b','a','s','l','i','y','o','r',0x0d,0x0a,0
msg_http_missing:
    .short 'H','a','t','a',':',' ','H','T','T','P',' ','p','r','o','t','o','k','o','l','u',' ','b','u','l','u','n','a','m','a','d','i',0x0d,0x0a,0
msg_http_config_fail:
    .short 'H','a','t','a',':',' ','H','T','T','P',' ','C','o','n','f','i','g','u','r','e',' ','b','a','s','a','r','i','s','i','z',0x0d,0x0a,0
msg_post_ok:
    .short '.',0
msg_post_err:
    .short '!',0x0d,0x0a,0

/* ============================================================
 * Writable data.
 * ============================================================ */
.section .data,"dw"
.p2align 3
g_boot_services: .quad 0
g_con_out:       .quad 0
g_sfs:           .quad 0
g_root:          .quad 0
g_file:          .quad 0
g_read_size:     .quad 0
g_exit_status:   .quad 0
g_msg_banner_ptr: .quad msg_banner

/* HTTP handles and event */
g_http:          .quad 0
g_http_event:    .quad 0
g_event_index:   .quad 0

/* EFI_HTTP_CONFIG_DATA (simplified, IPv4 default address) */
.p2align 3
http_config:
    .long 1                  /* HttpVersion = HTTP/1.1 */
    .long 0                  /* TimeOutMillisec = 0 */
    .byte 0                  /* LocalAddressIsIPv6 = FALSE */
    .zero 7                  /* padding */
    .quad http_v4_node       /* AccessPoint.IPv4Node */

http_v4_node:
    .byte 1                  /* UseDefaultAddress = TRUE */
    .zero 3                  /* LocalAddress */
    .zero 4                  /* LocalSubnet */
    .word 0                  /* LocalPort */

/* EFI_HTTP_REQUEST_DATA */
.p2align 3
g_http_request_data:
    .long HTTP_METHOD_POST   /* Method */
    .zero 4                  /* padding */
    .quad hedef_url          /* Url */

/* EFI_HTTP_MESSAGE */
.p2align 3
g_http_message:
    .quad 0                  /* Data.Request (filled at runtime) */
    .quad 0                  /* HeaderCount */
    .quad 0                  /* Headers */
    .quad 0                  /* BodyLength */
    .quad 0                  /* Body */

/* EFI_HTTP_TOKEN */
.p2align 3
g_http_token:
    .quad 0                  /* Event */
    .quad 0                  /* Status */
    .quad 0                  /* Message */

.section .bss,"bw"
.p2align 4
g_ascii_buf:     .zero MAX_READ
g_utf16_buf:     .zero (MAX_READ + 1) * 2
