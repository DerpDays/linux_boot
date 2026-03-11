#import "@preview/touying:0.6.1": *
#import themes.simple: *

#show: simple-theme.with(aspect-ratio: "16-9")

#title-slide([
  = Linux Boot Process
  // typos-lsp: ignore
  By Alexandre Pinheiro Dias
])

== Today
We will go over the general boot stages, and what is done in a typical linux
boot process.

The focus will be on UEFI in particular for the boot segment, as it is the
defacto modern standard for non-embedded devices now (and most UEFI firmware
supports CSM for BIOS compatibility/emulation).


== General boot stages

- POST
- UEFI (security/initialisation)
- UEFI (bootloader - `boot services`)
- UEFI (kernel - `runtime services`)
- Linux (kernel initialisation)
- Linux (initramfs)
- Linux (init)

== POST (power on self test)
The POST phase is the first actual stage that occurs for all modern machines, it
is hardware dependent, and done by your UEFI firmware or BIOS.

#pause

The goal of the POST phase is to initialise hardware, setup interfaces (e.g. for
UEFI), and initialise internal state (for the UEFI firmware).



Relevant:\
#link("https://www.seabios.org/Execution_and_code_flow.html#post-phase")

#pagebreak()

This is part of the UEFI firmware's responsibility, typically provided by your
motherboard, one you installed e.g. coreboot, or usually OVMF for virtual
machines.


== UEFI

The UEFI boot process can be split into 3 general stages:
- Initialisation
- Boot services $arrow.l.long$ this is where we start caring for linux
  (bootloader)
- Runtime services $arrow.l.long$ at this point we have handed control to kernel


Relevant:\
#link("https://en.wikipedia.org/wiki/UEFI#Boot_stages")

#pagebreak()

=== Initialisation
- SEC Phase
  - Tiny phase with platform specific code to initialise a tiny memory buffer,
    some architecture microcode, and in some cases, verifying later stages using
    a system secure element (e.g. TPM).\
    After this is done, it passes on information to the next stage (PEI).
#pagebreak()
- Pre-EFI Initialisation (PEI)
  - Handles early hardware tasks, like setting up the main memory (memory
    controllers etc.)
  - Handles any firmware recovery/flashing
  - Has a concept of PEI modules, which are minimal drivers which initialise
    hardware, such as the chipset, CPU, etc.
  - Handles dispatching these modules, manages dependencies between them, and
    handles their interfaces (called PPI).

#link("https://uefi.org/specs/PI/1.8/V1_Services_PEI.html")


#pagebreak()
- Driver Execution Environment (DXE)
  - This stage handles assigning `Device Path`'s to all connected hardware.
  - Code at this stages is finally typically platform-independent.
  - Also sets up the boot services protocol interface

#pagebreak()
Device paths are a flexible sequence of nodes describing a path from the UEFI
root to the given resource.

An entire device path can be made up of multiple device path instances, and each
instance is made up of multiple device path nodes. A device path may contain
multiple device-path instances - though atypical.

Each node represents a step in the path: PCI device, partition, filesystem, file
path, etc.

#pagebreak()
Here's an example of a device path, with two instances!
#text(
  `┌──────┬──────┬──────────────╥───────┬──────────┬────────────┐
│ ACPI │ PCI  │ END_INSTANCE ║ CDROM │ FILEPATH │ END_ENTIRE │
└──────┴──────┴──────────────╨───────┴──────────┴────────────┘
↑      ↑      ↑              ↑       ↑          ↑            ↑
├─Node─╨─Node─╨─────Node─────╨─Node──╨───Node───╨────Node────┤
↑                            ↑                               ↑
├─── DevicePathInstance ─────╨────── DevicePathInstance ─────┤
│                                                            │
└──────────────────── Entire DevicePath ─────────────────────┘`,
  size: 12pt,
  top-edge: 0em,
)

Well explain reference:\
#link("https://docs.rs/uefi/latest/uefi/proto/device_path")

#pagebreak()
Moving on, the next stage is:
- Boot Device Select (BDS)
  - This isn't mandatory (I believe), but is typical in all consumer devices.
  - This reads boot entries from the NVRAM, these can be managed in linux with
    `efibootmgr`!
  - Depending on the device, it may prompt a boot menu for users to select the
    an option.

#pagebreak()
- Transient System Load (TSL)
  - This phase actually loads the EFI program at the given path (or tries to
    find one on the EFI partition).

EFI partitions are FAT32 partitions (with some slight changes - though not well
documented/and don't make much difference).

Conversely, sticking to the windows theme, EFI applications are PE32 (32bit
windows portable executables) executables!

#pagebreak()
There are standard paths that are typically searched for EFI programs, if
booting from the device, such as `/efi/boot/bootx86.efi`, and more!

E.g. one for removable media (such as USB sticks), where they should place EFI
programs.

#pagebreak()
At this point, the linux kernel can already handle loading itself, as with
modern kernel versions, the kernel can act as a EFI (PE32) executable!

Though typically, people may have a separate bootloader between these phases,
for example:
- grub, rEFInd, systemd-boot

Newer bootloaders such as systemd-boot just boot the kernel as an EFI stub!

This is the type of bootloader we will create

== UEFI Bootloader
Lets get into our UEFI bootloader, this is in the UEFI Boot Services stage.

The main things our bootloader needs to do:
- Load the kernel to memory (or let the UEFI firmware do it by providing a path)
- Set load options, this lets us provide `cmdline` options to the kernel
- Swap the current executing image to the kernel efi image, and exit boot
  services.

#pagebreak()

Though as initramfs' (initrd), are typically required for booting, with the
setup above, we would need to include the initramfs in the actual kernel image.

Typically, we also require the initramfs to be built in for secure boot as well,
which is usually done by `ukify`, which creates a EFI application containing the
kernel, and the initramfs, and boots it!

#pagebreak()
This means that there must be a way to load the initramfs in our bootloader!

UEFI provides a EFI system table where we can provide configuration options,
conveniently, in the kernel `includes/linux/efi.h`, we are provided a big magic
list of GUID's (global unique identifiers), which we can use.

`#define LINUX_EFI_INITRD_MEDIA_GUID		EFI_GUID(0x5568e427, 0x68fc, 0x4f3d,  0xac, 0x74, 0xca, 0x55, 0x52, 0x31, 0xcc, 0x68)`

#pagebreak()
And looking there, we find an entry for the `initrd` media! We can insert into
the configuration table this entry, with a pointer to where we have loaded the
initramfs (given we have done that already), along with the size.

It is important that this allocation lives longer than the boot services stage,
and the UEFI provides protocols to do this, dictating how long it can live!

What we want is our allocation to live for the runtime phase (whenever the
kernel is alive).

== Linux kernel starting
The first steps the linux kernel takes is to decompress itself.

#link("https://0xax.gitbooks.io/linux-insides/content/Initialization/")

== Initramfs (initrd)
The initramfs' role is to open the root filesystem, and all devices that are
needed. Then launch the init program (e.g. systemd).

These are typically generated by a program, such as `dracut`, `mkinitcpio`, etc.

These provide modules & hooks (snippets), which are typically merged into a
shell script, which is executed, these might be: decrypting a LUKS device,
starting a bootsplash (plymouth), setting keyboard keymaps, logging, and of
course, mounting the root filesystem!

These modules typically allow extra configuration at runtime by editing the
linux commandline.

#pagebreak()


It is important to note, you don't actually need to have a shell, or other
programs in your initramfs, you could make a static executable which invokes
syscalls to do all this!

Though a shell + mini userspace is typically chosen as it allows for a nice
recovery environment if something fails, etc.


Typically people choose to use `busybox`, compiled statically, which provides
lots of utilities, such as `sh`, `mount`, etc.

#pagebreak()

One important thing to note, is that /dev is not populated by default, this
means you need to either manually create the device nodes (such as with
`mknod`), or by copying them from a working machine, or rely on the kernel to
make them for you!

We can make mount a devtmpfs (which the kernel then makes all the devices we
would expect), using the corresponding mount type.

With busybox: `mount -t devtmpfs none /dev`\
(where none means were not actually mounting a real device - virtual)







== Init

The init process (pid 1), must start all other programs. Conversely, this means
that if init is killed, all other programs will be killed (due to the nature of
the linux process tree).

Fun fact: if the `init` process is killed, the kernel will panic (and give you a
blue screen!)

PID 0 is reserved for the scheduler!

#pagebreak()


Typical programs that might be ran by the init system include:
- agetty (for logging in on the vt's)
- sshd (for ssh)
- logging/journal (journald, rsyslog, etc.)
- network (systemd-networkd, networkmanager, iwd, etc.)

#pagebreak()








//
//
//
//
// - Linux (kernel)
//   - get entries from drives (how exactly is dependent on partition table - e.g.
//     MBR vs GPT)
// - Load .efi file from ESP partition
//   - This is a #link("https://en.wikipedia.org/wiki/EFI_system_partition")[FAT32
//       partition]
//   - Actually just a windows PE executable, and linux kernel stubs just make
//     themselves into executables!
//   - UEFI has a bunch of functions available such as printing text to screen etc.
//
// These executables boot the actual kernel.
//
// In the case of linux, for more modern boot loaders such as systemd-boot, this
// literally just executes the linux kernel efi stub.
//
//
// == General linux stages
// - Kernel loaded into memory, this might involve a decompression stage if you
//   chose to compress the kernel.
// - Parse kernel command line arguments
// - Setups the builtin devices (e.g. CPU, GPU if module=y i believe, etc.),
//   pagetables, interrupts, etc.
//
//
