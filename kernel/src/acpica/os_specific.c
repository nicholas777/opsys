#include <stdarg.h>
#include <stdbool.h>

#define ACPI_CACHE_T                ACPI_MEMORY_LIST
#define ACPI_USE_LOCAL_CACHE        1

#include "acpi.h"
#include "libc_base.h"
#include "printf/printf.h"

#define printf__(format) 
//printf_(format); printf_("\n");

// Needed for using EFi as platform
UINT64
DivU64x32(UINT64 Dividend, UINT32 Divisor, UINT32 *Remainder) {
    UINT64 result = Dividend / Divisor;
    *Remainder = Dividend % Divisor;

    return result;
}


ACPI_STATUS
AcpiOsInitialize() {
    printf__("AcpiOsInitialize");
    AcpiDbgLevel = ACPI_DEBUG_ALL;

    return AE_OK;
}

ACPI_STATUS
AcpiOsTerminate() {
    printf__("AcpiOsTerminate");
    return AE_OK;
}

extern size_t rsdp_addr;

ACPI_PHYSICAL_ADDRESS
AcpiOsGetRootPointer() {
    return rsdp_addr;
}

ACPI_STATUS
AcpiOsPredefinedOverride(
    const ACPI_PREDEFINED_NAMES *InitVal,
    ACPI_STRING *NewVal
) {
    printf__("AcpiOsPredefinedOverride");

    *NewVal = NULL;
    return AE_OK;
}

ACPI_STATUS
AcpiOsTableOverride(
    ACPI_TABLE_HEADER *ExistingTable,
    ACPI_TABLE_HEADER **NewTable
) {
    printf__("AcpiOsTableOverride");
    return AE_NOT_IMPLEMENTED;
}

ACPI_STATUS
AcpiOsPhysicalTableOverride(
    ACPI_TABLE_HEADER *ExistingTable,
    ACPI_PHYSICAL_ADDRESS *NewAddress,
    UINT32 *NewTableLength
) {
    printf__("AcpiOsPhysicalTableOverride");
    return AE_NOT_IMPLEMENTED;
}

ACPI_STATUS
AcpiOsCreateLock(ACPI_SPINLOCK *OutHandle) {
    printf__("AcpiOsCreateLock");
    *OutHandle = AcpiOsAllocate(4);
    if (*OutHandle == NULL) return AE_NO_MEMORY;

    return AE_OK;
}

void
AcpiOsDeleteLock(ACPI_SPINLOCK Handle) {
    printf__("AcpiOsDeleteLock");
    AcpiOsFree(Handle);
}

ACPI_CPU_FLAGS
AcpiOsAcquireLock(ACPI_SPINLOCK Handle) {
    printf__("AcpiOsAquireLock");
    *(size_t *)Handle = 1;
    return 0;
}

void
AcpiOsReleaseLock(ACPI_SPINLOCK Handle, ACPI_CPU_FLAGS Flags) {
    printf__("AcpiOsReleaseLock");
    *(size_t *)Handle = 0;
}

ACPI_STATUS
AcpiOsCreateSemaphore(UINT32 MaxUnits, 
        UINT32 InitialUnits, ACPI_SEMAPHORE *OutHandle) {
    printf__("AcpiOsCreateSemaphore");

    *OutHandle = AcpiOsAllocate(4);
    if (*OutHandle == NULL) return AE_NO_MEMORY;

    *(size_t*)(*OutHandle) = InitialUnits;
    return AE_OK;
}

ACPI_STATUS
AcpiOsDeleteSemaphore(ACPI_SEMAPHORE Handle) {
    printf__("AcpiOsDeleteSemaphore");
    AcpiOsFree(Handle);

    return AE_OK;
}

ACPI_STATUS
AcpiOsWaitSemaphore(ACPI_SEMAPHORE Handle, UINT32 Units, UINT16 Timeout) {
    printf__("AcpiOsWaitSemaphore");
    if (Units > *(size_t *)Handle) return AE_BAD_PARAMETER;
    *(size_t *)Handle -= Units;

    return AE_OK;
}

ACPI_STATUS
AcpiOsSignalSemaphore(ACPI_SEMAPHORE Handle, UINT32 Units) {
    printf__("AcpiOsSignalSemaphore");
    *(size_t *)Handle += Units;
    return AE_OK;
}

extern uint8_t *
c_alloc(uint32_t size, uint32_t align);

extern uint8_t *
c_free(void *memory);

void *
AcpiOsAllocate(ACPI_SIZE Size) {
    printf__("AcpiOsAllocate");
    return (void *)c_alloc((uint32_t)Size, 
            PLATFORM_BITS == 32 ? 4 : 8);
}

void
AcpiOsFree(void *Memory) {
    printf__("AcpiOsFree");
    c_free(Memory);
}

extern size_t 
c_mapPageN(size_t addr, size_t n);

extern void 
c_freePage(size_t addr);

void *
AcpiOsMapMemory(ACPI_PHYSICAL_ADDRESS where, ACPI_SIZE length) {
    printf__("AcpiOsMapMemory");
    size_t n_pages = 0;
    const size_t offset = where % 4096;
    const size_t boundary = where - offset;

    if ((length / 4096) * 4096 == length) 
        n_pages = length / 4096;
    else 
        n_pages = length / 4096 + 1;

    void *ptr = (void *)c_mapPageN(boundary, n_pages);
    return ptr + offset;
}

void
AcpiOsUnmapMemory(void *LogicalAddress, ACPI_SIZE size) {
    printf__("AcpiOsUnmapMemory");
    size_t n_pages = 0;
    const size_t boundary = (size_t)LogicalAddress - ((size_t)LogicalAddress % 4096);

    if ((size / 4096) * 4096 == size) 
        n_pages = size / 4096;
    else 
        n_pages = size / 4096 + 1;

    for (size_t i = 0; i < n_pages; i++) {
        c_freePage(boundary + i * 4096);
    }

}

ACPI_STATUS
AcpiOsGetPhysicalAddress(
    void *LogicalAddress, 
    ACPI_PHYSICAL_ADDRESS *PhysicalAddress
) {
    printf__("AcpiOsGetPhysicalAddress");
    return AE_NOT_IMPLEMENTED;
}

extern void
installIntHandler(void *handler, size_t n, void *context);

extern void
uninstallIntHandler(size_t n);

ACPI_STATUS
AcpiOsInstallInterruptHandler (
    UINT32 InterruptNumber,
    ACPI_OSD_HANDLER ServiceRoutine,
    void *Context
) {
    printf__("AcpiOsInstallInterruptHandler");
    installIntHandler((void *)ServiceRoutine, InterruptNumber, Context);
    return AE_OK;
}

ACPI_STATUS
AcpiOsRemoveInterruptHandler(
    UINT32 InterruptNumber,
    ACPI_OSD_HANDLER ServiceRoutine
) {
    printf__("AcpiOsRemoveInterruptHandler");
    uninstallIntHandler(InterruptNumber);
    return AE_OK;
}


ACPI_THREAD_ID
AcpiOsGetThreadId() {
    printf__("AcpiOsGetThreadId");
    return 1;
}

ACPI_STATUS
AcpiOsExecute(
    ACPI_EXECUTE_TYPE Type,
    ACPI_OSD_EXEC_CALLBACK Function,
    void *Context
) {
    printf__("AcpiOsExecute");
    return AE_NOT_IMPLEMENTED;
}

void
AcpiOsWaitEventsComplete() {
    printf__("AcpiOsWaitEventsComplete");
}

void
AcpiOsSleep(UINT64 Milliseconds) {
    printf__("AcpiOsSleep");
}

void
AcpiOsStall(UINT32 Microseconds) {

    printf__("AcpiOsStall");
}

ACPI_STATUS
AcpiOsReadPort(ACPI_IO_ADDRESS Address, UINT32 *Value, UINT32 Width) {
    printf__("AcpiOsReadPort");

    uint32_t result;
    if (Width == 8) {
        asm volatile (
            "inb %1"
            : "=a" (result)
            : "d" ((uint16_t)Address)
        );
    } else if (Width == 16) {
        asm volatile (
            "inw %1"
            : "=a" (result)
            : "d" ((uint16_t)Address)
        );
    } else if (Width == 32) {
        asm volatile (
            "inl %1"
            : "=a" (result)
            : "d" ((uint16_t)Address)
        );
    }

    *Value = result;

    return AE_OK;
}

ACPI_STATUS
AcpiOsWritePort(ACPI_IO_ADDRESS Address, UINT32 Value, UINT32 Width) {
    printf__("AcpiOsWritePort");

    if (Width == 8) {
        asm volatile (
            "outb %0"
            : : "d" ((uint16_t)Address), "a" ((uint8_t)Value)
        );
    } else if (Width == 16) {
        asm volatile (
            "outw %0"
            : : "d" ((uint16_t)Address), "a" (Value)
        );
    } else if (Width == 32) {
        asm volatile (
            "outl %0"
            : : "d" ((uint16_t)Address), "a" (Value)
        );
    } else {
    }

    return AE_OK;
}


ACPI_STATUS
AcpiOsReadMemory(ACPI_PHYSICAL_ADDRESS Address, UINT64 *Value, UINT32 Width) {
    printf__("AcpiOsReadMemory");
    return AE_NOT_IMPLEMENTED;
}

ACPI_STATUS
AcpiOsWriteMemory(ACPI_PHYSICAL_ADDRESS Address, UINT64 Value, UINT32 Width) {
    printf__("AcpiOsWriteMemory");
    return AE_NOT_IMPLEMENTED;
}

ACPI_STATUS
AcpiOsReadPciConfiguration(
    ACPI_PCI_ID *PciId,
    UINT32 Reg,
    UINT64 *Value,
    UINT32 Width
) {
    printf__("AcpiOsReadPciConfiguration");
    return AE_NOT_IMPLEMENTED;
}

ACPI_STATUS
AcpiOsWritePciConfiguration(
    ACPI_PCI_ID *PciId,
    UINT32 Reg,
    UINT64 Value,
    UINT32 Width
) {
    printf__("AcpiOsWritePciConfiguration");
    return AE_NOT_IMPLEMENTED;
}


BOOLEAN
AcpiOsReadable(void *Pointer, ACPI_SIZE Length) {
    printf__("AcpiOsReadable");
    return false;
}

BOOLEAN
AcpiOsWritable(void *Pointer, ACPI_SIZE Length) {
    printf__("AcpiOsWritable");
    return false;
}

UINT64
AcpiOsGetTimer() {
    printf__("AcpiOsGetTimer");
    return 0;
}

ACPI_STATUS
AcpiOsSignal(UINT32 Function, void *Info) {
    printf__("AcpiOsSignal");
    return AE_NOT_IMPLEMENTED;
}

ACPI_STATUS
AcpiOsEnterSleep(UINT8 SleepState, UINT32 RegaValue, UINT32 RegbValue) {
    printf__("AcpiOsEnterSleep");
    return AE_NOT_IMPLEMENTED;
}

ACPI_PRINTF_LIKE(1) 
void ACPI_INTERNAL_VAR_XFACE
AcpiOsPrintf(const char *format, ...) {
    va_list args;
    va_start(args, format);

    vprintf_(format, args);
}

void
AcpiOsVprintf(const char *format, va_list args) {
    vprintf_(format, args);
}

void
AcpiOsRedirectOutput(void *Destination) {
    printf__("AcpiOsRedirectOutput");
}

ACPI_STATUS
AcpiOsGetLine(
    char *Buffer,
    UINT32 BufferLength,
    UINT32 *BytesRead
) {
    printf__("AcpiOsGetLine");
    return AE_NOT_IMPLEMENTED;
}

ACPI_STATUS
AcpiOsInitializeDebugger() {
    printf__("AcpiOsInitializeDebugger");
    return AE_NOT_IMPLEMENTED;
}

void
AcpiOsTerminateDebugger() {
    printf__("AcpiOsTerminateDebugger");
}

ACPI_STATUS
AcpiOsWaitCommandReady() {
    printf__("AcpiOsWaitCommandReady");
    return AE_NOT_IMPLEMENTED;
}

ACPI_STATUS
AcpiOsNotifyCommandComplete() {
    printf__("AcpiOsNotifyCommandComplete");
    return AE_NOT_IMPLEMENTED;
}

void
AcpiOsTracePoint(
    ACPI_TRACE_EVENT_TYPE Type,
    BOOLEAN Begin,
    UINT8 *Aml,
    char *Pathname
) {
    printf__("AcpiOsTracePoint");
}


ACPI_STATUS
AcpiOsGetTableByName(
    char *Signature, 
    UINT32 Instance, 
    ACPI_TABLE_HEADER **Table, 
    ACPI_PHYSICAL_ADDRESS *Address
) {
    printf__("AcpiOsGetTableByName");
    return AE_NOT_IMPLEMENTED;
}

ACPI_STATUS
AcpiOsGetTableByIndex(
    UINT32 Index, 
    ACPI_TABLE_HEADER **Table, 
    UINT32 *Instance, 
    ACPI_PHYSICAL_ADDRESS *Address
) {
    printf__("AcpiOsGetTableByIndex");
    return AE_NOT_IMPLEMENTED;
}

ACPI_STATUS
AcpiOsGetTableByAddress(ACPI_PHYSICAL_ADDRESS Address, ACPI_TABLE_HEADER **Table) {
    printf__("AcpiOsGetTableByAddress");
    return AE_NOT_IMPLEMENTED;
}

void *
AcpiOsOpenDirectory(char *Pathname, char *WildcardSpec, char RequestedFileType) {
    printf__("AcpiOsOpenDirectory");
    return NULL;
}

char *
AcpiOsGetNextFilename(void *DirHandle) {
    printf__("AcpiOsGetNextFilename");
    return NULL;
}

void
AcpiOsCloseDirectory(void *DirHandle) {
    printf__("AcpiOsCloseDirectory");
}

