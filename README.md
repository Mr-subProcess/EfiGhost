╔══════════════════════════════════════════════════════════════════════════╗
║                    UEFI HTTP POST MODULE — README                        ║
║                    Version 1.0  |  x86-64 UEFI                           ║
╚══════════════════════════════════════════════════════════════════════════╝

⚠️  DISCLAIMER OF LIABILITY
════════════════════════════════════════════════════════════════════════════
THIS SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT.

THE AUTHOR ACCEPTS NO RESPONSIBILITY OR LIABILITY WHATSOEVER FOR ANY DIRECT,
INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES ARISING
IN ANY WAY OUT OF THE USE, MISUSE, INABILITY TO USE, OR RELIANCE UPON THIS
SOFTWARE, ITS SOURCE CODE, ITS DOCUMENTATION, OR ANY DERIVED WORK.

YOU ARE SOLELY RESPONSIBLE FOR:
  • Compliance with all applicable laws and regulations in your jurisdiction.
  • Obtaining explicit permission before transmitting any data to any server.
  • Ensuring the security, integrity, and confidentiality of any data handled.
  • Any damage to hardware, firmware, data, or systems caused by this code.
  • Any violation of network policies, terms of service, or privacy laws
    (e.g., GDPR, KVKK, CCPA) resulting from your use of this module.

THIS MODULE IS INTENDED FOR EDUCATIONAL AND RESEARCH PURPOSES ONLY.
DO NOT DEPLOY IN PRODUCTION, ON SYSTEMS YOU DO NOT OWN, OR IN ANY CONTEXT
WHERE UNAUTHORIZED DATA TRANSMISSION MAY OCCUR.


╔══════════════════════════════════════════════════════════════════════════╗
║  1. OVERVIEW                                                             ║
╚══════════════════════════════════════════════════════════════════════════╝

This project is a low-level UEFI module that runs BEFORE any operating
system is loaded (pre-boot environment). It executes directly on the UEFI
firmware and reads a text file from the EFI System Partition (ESP), then
continuously POSTs its contents to an HTTP server.

The module uses UEFI's built-in EFI_SIMPLE_FILE_SYSTEM_PROTOCOL and
EFI_HTTP_PROTOCOL services directly. It requires no operating system
component, no driver, and no user-space library.

Target:      x86-64 UEFI (EFI Application)
Language:    GNU Assembly (.intel_syntax noprefix)
ABI:         Microsoft x64 (UEFI specification)
Dependencies: None (no EDK II / GNU-EFI required)


╔══════════════════════════════════════════════════════════════════════════╗
║  1.1 THIS IS A MODULE, NOT AN APPLICATION                                ║
╚══════════════════════════════════════════════════════════════════════════╝

This code is NOT a standalone end-user application. It is designed as a
MODULE intended to be integrated into another UEFI application or firmware
component. Its routines (post_setup, post_loop, post_close_event, post_skip)
are isolated, side-effect-limited, and structured for reuse.


╔══════════════════════════════════════════════════════════════════════════╗
║  1.2 WHAT IT DOES                                                        ║
╚══════════════════════════════════════════════════════════════════════════╝

  1. Locates \veri.txt on the ESP and opens it in read mode.
  2. Reads at most 256 bytes from the file.
  3. Converts the raw bytes to ASCII-safe UTF-16 and prints them on screen.
  4. Locates EFI_HTTP_PROTOCOL and configures it with Configure().
  5. Enters an INFINITE LOOP. Each iteration:
       - Rewinds the file to position 0 (SetPosition(0)).
       - Re-reads the file (so external updates are picked up).
       - Creates a new EFI_EVENT.
       - Populates EFI_HTTP_REQUEST_DATA, EFI_HTTP_MESSAGE, EFI_HTTP_TOKEN.
       - Queues an asynchronous POST via Request().
       - Waits for completion via WaitForEvent().
       - Checks Token->Status: prints '.' on success, '!' on failure.
       - Closes the event with CloseEvent().
       - Sleeps 1 second via Stall(1_000_000) and repeats.


╔══════════════════════════════════════════════════════════════════════════╗
║  1.3 WHAT IT DOES NOT DO                                                 ║
╚══════════════════════════════════════════════════════════════════════════╝

  ✗ Does NOT implement a TCP/IP stack — uses the firmware's stack via
    EFI_TCP4 / EFI_TCP6 underneath EFI_HTTP_PROTOCOL.
  ✗ Does NOT perform TLS/HTTPS — only http:// is supported. Can be extended
    with EFI_TLS_PROTOCOL (see §7).
  ✗ Does NOT resolve DNS — the URL must be a direct IP address or a
    hostname already cached by the firmware. Can be extended with
    EFI_DNS4_PROTOCOL (see §7).
  ✗ Does NOT include a Wi-Fi driver — works only if the firmware already
    provides a network connection (Ethernet, Wi-Fi, USB-NIC).
  ✗ Does NOT keep the system alive indefinitely — disables the watchdog
    via SetWatchdogTimer(0, ...) to prevent a 5-minute reset.


╔══════════════════════════════════════════════════════════════════════════╗
║  2. ARCHITECTURE                                                         ║
╚══════════════════════════════════════════════════════════════════════════╝

    ┌─────────────────────────────────────────────────────────┐
    │                    UEFI Firmware                        │
    │  ┌───────────────────────────────────────────────────┐  │
    │  │  EFI_BOOT_SERVICES                                │  │
    │  │  ├─ LocateProtocol (SFS, HTTP)                    │  │
    │  │  ├─ CreateEvent / WaitForEvent / CloseEvent       │  │
    │  │  ├─ Stall                                         │  │
    │  │  └─ SetWatchdogTimer                              │  │
    │  ├───────────────────────────────────────────────────┤  │
    │  │  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL                  │  │
    │  │  └─ OpenVolume → EFI_FILE_PROTOCOL                │  │
    │  │       ├─ Open / Read / SetPosition / Close        │  │
    │  ├───────────────────────────────────────────────────┤  │
    │  │  EFI_HTTP_PROTOCOL                                │  │
    │  │  ├─ Configure                                     │  │
    │  │  └─ Request  (over TCP4/TCP6)                     │  │
    │  └───────────────────────────────────────────────────┘  │
    └─────────────────────────────────────────────────────────┘
            ▲                                      │
            │ efi_main(ImageHandle, SystemTable)   │ HTTP POST
            │                                      ▼
    ┌───────┴──────────┐                 ┌────────────────────┐
    │  BOOTX64.EFI     │                 │  Target HTTP Server│
    │  (this module)   │                 │  (e.g. 192.168.x)  │
    └──────────────────┘                 └────────────────────┘
            │
            │ Read
            ▼
    ┌──────────────────┐
    │  ESP:\veri.txt   │  ← Configurable data source
    └──────────────────┘


╔══════════════════════════════════════════════════════════════════════════╗
║  3. TECHNICAL SPECIFICATION                                              ║
╚══════════════════════════════════════════════════════════════════════════╝

3.1 UEFI structures used
────────────────────────
  EFI_SYSTEM_TABLE          ~120 bytes   ConOut, BootServices access
  EFI_BOOT_SERVICES         ~240 bytes   Events, protocol lookup, stall
  EFI_FILE_PROTOCOL         ~72 bytes    File open/read/seek
  EFI_HTTP_PROTOCOL         ~40 bytes    Configure + Request
  EFI_HTTP_CONFIG_DATA      24 bytes     Connection configuration
  EFI_HTTP_REQUEST_DATA     16 bytes     Method + URL
  EFI_HTTP_MESSAGE          40 bytes     Request body and headers
  EFI_HTTP_TOKEN            24 bytes     Async operation descriptor

3.2 Verified offsets (UEFI Spec 2.10)
─────────────────────────────────────
  SystemTable->ConOut                    0x40
  SystemTable->BootServices              0x60
  BootServices->CreateEvent              0x50   (FreePool = 0x48!)
  BootServices->WaitForEvent             0x60   (SetTimer = 0x58!)
  BootServices->CloseEvent               0x70   (SignalEvent = 0x68!)
  BootServices->LocateProtocol           0x140
  BootServices->Stall                    0xF8
  BootServices->SetWatchdogTimer         0x100
  SimpleFileSystem->OpenVolume           0x08
  File->Open                             0x08
  File->Close                            0x10
  File->Read                             0x20
  File->SetPosition                      0x38
  HTTP->Configure                        0x08   (GetModeData = 0x00)
  HTTP->Request                          0x10

3.3 GUIDs (little-endian byte order)
────────────────────────────────────
  EFI_SIMPLE_FILE_SYSTEM_PROTOCOL
    964E5B22-6459-11D2-8E39-00A0C969723B
    22 5B 4E 96 59 64 D2 11 8E 39 00 A0 C9 69 72 3B

  EFI_HTTP_PROTOCOL
    7A59B29B-910B-4171-8242-A85A0DF25B5B
    9B B2 59 7A 0B 91 71 41 82 42 A8 5A 0D F2 5B 5B

3.4 ABI details
───────────────
  Calling convention:  Microsoft x64 (RCX, RDX, R8, R9; args 5+ on stack
                       starting at [rsp+0x20])
  Shadow space:        At least 32 bytes reserved before each call
                       (sub rsp, 40 → 32 shadow + 8 alignment)
  Stack alignment:     rsp must be 16-byte aligned at the call
                       (entry rsp is 8 mod 16; sub rsp, 40 fixes this)
  Nonvolatile:         rbx, rbp, rdi, rsi, r12-r15 (this module avoids them)
  Volatile:            rax, rcx, rdx, r8-r11


╔══════════════════════════════════════════════════════════════════════════╗
║  4. BUILDING                                                             ║
╚══════════════════════════════════════════════════════════════════════════╝

4.1 Requirements
────────────────
  clang             10+    (Debian/Ubuntu: clang)
  lld-link          10+    (Debian/Ubuntu: lld)
  mtools            4.0+   (Debian/Ubuntu: mtools)
  qemu-system-x86_64 5.0+  (Debian/Ubuntu: qemu-system-x86)
  ovmf              any    (Debian/Ubuntu: ovmf)

4.2 Build command
─────────────────
  # Assembly → COFF object
  clang --target=x86_64-pc-win32-coff -c uefi_post.S -o uefi_post.obj

  # COFF → PE32+ EFI Application
  lld-link /subsystem:efi_application /entry:efi_main /nodefaultlib \
           /out:BOOTX64.EFI uefi_post.obj

4.3 Verify
──────────
  file BOOTX64.EFI
  # Expected: "PE32+ executable (EFI application) x86-64"

  objdump -h BOOTX64.EFI | head
  # Expected sections: .text, .rdata, .data, .bss


╔══════════════════════════════════════════════════════════════════════════╗
║  5. TEST ENVIRONMENT                                                     ║
╚══════════════════════════════════════════════════════════════════════════╝

5.1 Prepare FAT32 ESP image
───────────────────────────
  dd if=/dev/zero of=uefi.img bs=1M count=64
  mkfs.vfat -F 32 uefi.img
  mmd -i uefi.img ::/EFI
  mmd -i uefi.img ::/EFI/BOOT
  mcopy -i uefi.img BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI
  mcopy -i uefi.img veri.txt    ::/veri.txt

5.2 Run with QEMU
─────────────────
  qemu-system-x86_64 \
      -bios /usr/share/ovmf/OVMF.fd \
      -drive format=raw,file=uefi.img \
      -netdev user,id=net0 \
      -device e1000,netdev=net0

  ⚠  -netdev user -device e1000 is MANDATORY. Without it, OVMF cannot
     initialize its TCP/IP stack and Configure() will fail.

5.3 Test receiver (Python)
──────────────────────────
  from http.server import BaseHTTPRequestHandler, HTTPServer

  class H(BaseHTTPRequestHandler):
      def do_POST(self):
          n = int(self.headers.get('Content-Length', 0))
          data = self.rfile.read(n)
          print(f'POST {self.path} [{n} B]: {data!r}')
          self.send_response(200)
          self.send_header('Content-Length', '2')
          self.end_headers()
          self.wfile.write(b'OK')

  HTTPServer(('0.0.0.0', 8080), H).serve_forever()

  QEMU user networking maps the host to 10.0.2.2 → set hedef_url to
  http://10.0.2.2:8080/api


╔══════════════════════════════════════════════════════════════════════════╗
║  6. ⭐ ADAPTING THE DATA SOURCE TO YOUR OWN SOFTWARE                     ║
╚══════════════════════════════════════════════════════════════════════════╝

The core advantage of this module is that the data source is ABSTRACTED
BEHIND A SINGLE FILE NAME. Instead of veri.txt, you can use any text file
produced by your own software, log, sensor output, or any other source.

6.1 Simplest adaptation: change the file name
─────────────────────────────────────────────
  Find this line in the .S file:

      filename:
          .short 'v','e','r','i','.','t','x','t',0

  Replace with your own UTF-16LE file name, e.g. sensor.log:

      filename:
          .short 's','e','n','s','o','r','.','l','o','g',0

  ⚠  UEFI file names are stored as UTF-16LE. Each .short directive emits
     2 bytes per character. For non-ASCII characters (e.g., Turkish 'ı'),
     use the Unicode codepoint (0x0131).

6.2 Reading from a different path
─────────────────────────────────
  To read a file inside a subdirectory, use an absolute path as the 3rd
  argument to EFI_FILE_PROTOCOL.Open:

      filename:
          .short '\\','l','o','g','s','\\','v','e','r','i','.','t','x','t',0

  UEFI file system protocol expects an absolute path with backslash
  separators (OpenVolume already returns the root).

6.3 Dynamic data source (externally updated file)
─────────────────────────────────────────────────
  The module performs SetPosition(0) + Read on EVERY iteration. This means:

    • As long as veri.txt is not changed inside the image, the same
      content is sent repeatedly.
    • However, if veri.txt is UPDATED EXTERNALLY (by another EFI
      application, a runtime driver, or a repartitioning tool), the next
      POST carries the new content.
    • This behavior makes the module ideal for LIVE DATA STREAMS: as
      another application writes to veri.txt, this module reads it.

  Example flow:

    [Another EFI app]                    [This module]
            │                                  │
            │  Write(veri.txt, "temp=42")      │
            ├─────────────────────────────────►│
            │                                  │ Read(veri.txt)
            │                                  │ POST("temp=42")
            │                                  │
            │  Write(veri.txt, "temp=43")      │
            ├─────────────────────────────────►│
            │                                  │ Read(veri.txt)
            │                                  │ POST("temp=43")

6.4 Sending in-memory data (instead of a file)
──────────────────────────────────────────────
  If your data is produced in memory (e.g., another module fills
  g_ascii_buf), you can disable the file-read block in post_loop and pass
  the buffer directly to POST:

      .post_loop:
          /* Skip file read, use g_ascii_buf directly */
          mov     qword ptr [rip + g_read_size], <actual_byte_count>
          jmp     .post_send

      .post_send:
          /* ... CreateEvent and the rest are unchanged ... */

  This turns the module into an EMBEDDABLE "POST sender service" that
  another UEFI application can reuse.

6.5 Suggested configuration for production
───────────────────────────────────────────
  Move the following constants into .data so they can be modified at
  runtime:

    MAX_READ (256)           → configurable buffer size
    hedef_url                → read from config.txt on the ESP
    filename                 → same
    Stall(1_000_000)         → configurable poll interval
    TPL_CALLBACK             → DO NOT change (callback context)

6.6 Multiple files / multiple POSTs
───────────────────────────────────
  Extend post_loop to POST several files in sequence:

      .post_loop_multi:
          call post_one_file       ; veri1.txt
          call post_one_file       ; veri2.txt
          call post_one_file       ; veri3.txt
          ; Stall + loop

  Implement post_one_file to take the file name in RCX.

6.7 Recommended data formats
────────────────────────────
  The POST body is sent as a RAW BYTE ARRAY. For easier server-side
  parsing, prefer:

    Plain text      temp=42                     simplest
    JSON            {"temp":42}                 needs Content-Type
    Key-value       k1=v1&k2=v2                 application/x-www-form-urlencoded
    Binary          raw bytes                   application/octet-stream

6.8 Adding Content-Type (optional)
──────────────────────────────────
  By default, the module sends NO headers (HeaderCount = 0). To send JSON,
  add an EFI_HTTP_HEADER array to EFI_HTTP_MESSAGE.Headers:

      ; EFI_HTTP_HEADER: FieldName (CHAR16*), FieldValue (CHAR16*)
      http_headers:
          .quad header_content_type_name
          .quad header_content_type_value

      header_content_type_name:
          .short 'C','o','n','t','e','n','t','-','T','y','p','e',0
      header_content_type_value:
          .short 'a','p','p','l','i','c','a','t','i','o','n','/','j','s','o','n',0

  And when filling EFI_HTTP_MESSAGE:

      mov     qword ptr [rax + 8], 1         ; HeaderCount = 1
      lea     rcx, [rip + http_headers]
      mov     qword ptr [rax + 16], rcx      ; Headers

  ⚠  Content-Length is usually added automatically by the UEFI HTTP stack,
     but some firmware versions require manual inclusion.


╔══════════════════════════════════════════════════════════════════════════╗
║  7. EXTENSION ROADMAP                                                    ║
╚══════════════════════════════════════════════════════════════════════════╝

7.1 HTTPS support (EFI_TLS_PROTOCOL)
────────────────────────────────────
  EFI_HTTP_PROTOCOL does not perform TLS by itself. For HTTPS, EFI_TLS_
  PROTOCOL and EFI_TLS_CONFIGURATION_PROTOCOL must be wired to HTTP via
  EFI_SERVICE_BINDING_PROTOCOL. This is a complex extension outside the
  scope of this module.

7.2 DNS resolution (EFI_DNS4_PROTOCOL)
──────────────────────────────────────
  To use a hostname in hedef_url, resolve it to an IP first via
  EFI_DNS4_PROTOCOL. The firmware's DNS cache is usually empty, so this
  step is practically mandatory.

7.3 Authentication
──────────────────
  For HTTP Basic Auth or token-based auth, add an Authorization header to
  the EFI_HTTP_HEADER array. Storing tokens inside the firmware is risky;
  reading them from a separate ESP file is safer.

7.4 Multiple target URLs
────────────────────────
  For load balancing or redundancy, extend the hedef_url array and POST
  to a different target each iteration. Add a g_current_target counter
  to post_loop.


╔══════════════════════════════════════════════════════════════════════════╗
║  8. ERROR HANDLING                                                       ║
╚══════════════════════════════════════════════════════════════════════════╝

8.1 Error codes
───────────────
  .bad_system_table       0x8000000000000002   SystemTable NULL
  .unsupported            0x8000000000000003   Required protocol missing
  .filesystem_missing     0x800000000000000e   SFS not found
  .file_missing           0x800000000000000e   veri.txt not found
  .io_error               0x8000000000000007   Read/write failure
  .empty_file             EFI_SUCCESS          File empty (not an error)
  .http_missing           EFI_UNSUPPORTED      HTTP protocol missing
  .http_config_fail       EFI_DEVICE_ERROR     Configure() failed

8.2 Loop-level error tolerance
──────────────────────────────
  Errors inside post_loop (SetPosition, Read, CreateEvent, Request,
  WaitForEvent, Token->Status) are NON-CRITICAL. The module prints '!'
  and resumes after a 1-second Stall. It only exits the loop if g_file
  is NULL (file closed).

  This design decision is intentional: SHORT NETWORK OUTAGES, SERVER
  RESTARTS, OR TRANSIENT HTTP ERRORS MUST NOT STOP THE MODULE.

8.3 After a critical error
──────────────────────────
  Errors inside efi_main (file open or HTTP configuration) call
  close_handles, clean up, and return EFI_STATUS. The firmware then
  returns to the shell or the next boot option.


╔══════════════════════════════════════════════════════════════════════════╗
║  9. TROUBLESHOOTING                                                      ║
╚══════════════════════════════════════════════════════════════════════════╝

  Symptom                          Cause                       Fix
  ─────────────────────────────────────────────────────────────────────
  Firmware won't load BOOTX64.EFI  Wrong Subsystem             Use
                                                               /subsystem:
                                                               efi_application
  "SFS not found"                  ESP not mounted / no FAT    Ensure image
                                                               is FAT32
  "veri.txt not found"             File not in ESP root        mcopy ... ::/
                                                               veri.txt
  "HTTP protocol not found"        OVMF too old / no NIC       Add -netdev
                                                               user -device
                                                               e1000
  "HTTP Configure failed"          http_config misaligned      Ensure
                                   or no network               AccessPoint
                                                               pointer is
                                                               8-byte
                                                               aligned
  Endless "!"                      Server unreachable          Check
                                                               hedef_url;
                                                               test with
                                                               python3 -m
                                                               http.server
  System resets after 5 min        Watchdog not disabled       Verify
                                                               BS_SET_WATCHDOG
                                                               = 0x100
  Garbage on screen                UTF-16 conversion bug       Check
                                                               mov word ptr
                                                               [r11 + r8*2], ax
  POST sent but not received       Routing / firewall          QEMU host =
                                                               10.0.2.2;
                                                               on real HW
                                                               check gateway


╔══════════════════════════════════════════════════════════════════════════╗
║  10. SECURITY NOTES                                                      ║
╚══════════════════════════════════════════════════════════════════════════╝

⚠  This module runs in a pre-boot environment and performs firmware-level
   network access. The following risks MUST be understood:

  1. Unencrypted communication:
     HTTP is used by default (plaintext). If you transmit sensitive data,
     add TLS (see §7.1).

  2. No authentication:
     The target server accepts any client. Add IP allow-listing or token
     verification on the server side.

  3. Hardcoded URL/credentials:
     hedef_url is plaintext inside the binary. Reverse engineering is
     trivial.

  4. Infinite loop:
     The module never returns from efi_main. The firmware cannot proceed
     to another boot option; the user must power off manually.

  5. Watchdog:
     If not disabled, the system resets after 5 minutes. If disabled,
     the module runs INDEFINITELY. This may be undesirable in production.

  Recommendations:
    • Use ONLY in development and test environments.
    • Add TLS + authentication before production use.
    • Add a MAXIMUM ITERATION limit (e.g., exit after 1000 POSTs).
    • Read hedef_url from a separate configuration file on the ESP.


╔══════════════════════════════════════════════════════════════════════════╗
║  11. FILE STRUCTURE                                                      ║
╚══════════════════════════════════════════════════════════════════════════╝

  .
  ├── uefi_post.S          Main module source
  ├── README.md            This file
  ├── veri.txt             Default data source (configurable)
  ├── BOOTX64.EFI          Compiled UEFI application (generated)
  └── uefi.img             FAT32 ESP test image (generated)


╔══════════════════════════════════════════════════════════════════════════╗
║  12. VERSION HISTORY                                                     ║
╚══════════════════════════════════════════════════════════════════════════╝

  1.0   Initial release. File read + HTTP POST loop. Watchdog disable.
        CreateEvent / WaitForEvent offsets verified against UEFI 2.10.


╔══════════════════════════════════════════════════════════════════════════╗
║  13. REFERENCES                                                          ║
╚══════════════════════════════════════════════════════════════════════════╝

  • UEFI Specification 2.10         — UEFI Forum (uefi.org/specifications)
  • EFI_HTTP_PROTOCOL               — UEFI Spec §30.3
  • EFI_SIMPLE_FILE_SYSTEM_PROTOCOL — UEFI Spec §13.4
  • EFI_FILE_PROTOCOL               — UEFI Spec §13.5
  • Microsoft x64 Calling Convention — learn.microsoft.com/en-us/cpp/build/
                                        x64-calling-convention
  • OVMF (Open Virtual Machine Firmware) — github.com/tianocore/edk2


╔══════════════════════════════════════════════════════════════════════════╗
║  FINAL WORD                                                              ║
╚══════════════════════════════════════════════════════════════════════════╝

  This module demonstrates how to send data over the network BEFORE any
  operating system loads — at the LOWEST level, WITHOUT any library, and
  ENTIRELY IN ASSEMBLY.

  By replacing veri.txt with data produced by your own software, you can
  adapt the module to your needs. All you have to change is the correct
  file name and the target URL.

  ⚠  USE AT YOUR OWN RISK. THE AUTHOR ACCEPTS NO RESPONSIBILITY FOR ANY
     CONSEQUENCES ARISING FROM THE USE OF THIS CODE.
