#![no_main]
#![no_std]

extern crate alloc;

use alloc::{borrow::ToOwned, boxed::Box, format, string::String, vec, vec::Vec};
use core::fmt::Write;
use core::time::Duration;
use core::{mem::MaybeUninit, ptr::NonNull};
use log::{error, info};
use uefi::proto::console::text::Key;
use uefi::{
    CStr16, Guid,
    boot::{LoadImageSource, get_image_file_system},
    prelude::*,
    proto::{
        device_path::{
            DevicePath, DevicePathNode, LoadedImageDevicePath,
            build::{BuildNode, DevicePathBuilder, media::FilePath},
        },
        loaded_image::LoadedImage,
        media::file::{File, FileAttribute, FileInfo, FileMode},
    },
};

const LINUX_PATH: &CStr16 = cstr16!("\\vmlinuz-linux");
const INITRD_PATH: &CStr16 = cstr16!("\\initramfs.cpio.gz");
const CMDLINE: &CStr16 = cstr16!("console=hvc0");

// https://github.com/torvalds/linux/blob/v7.0-rc3/include/linux/efi.h#L420
const LINUX_EFI_INITRD_MEDIA_GUID: Guid = Guid::new(
    0x5568e427_u32.to_le_bytes(),
    0x68fc_u16.to_le_bytes(),
    0x4f3d_u16.to_le_bytes(),
    0xac,
    0x74,
    [0xca_u8, 0x55_u8, 0x52_u8, 0x31_u8, 0xcc_u8, 0x68_u8],
);

#[repr(C)]
struct InitrdInfo {
    base: u64,
    size: u64,
}

#[entry]
fn main() -> Status {
    uefi::helpers::init().unwrap();

    // Wait for the user to press enter, here you could do selection of a kernel for example!
    await_press_enter();

    match boot_kernel() {
        Ok(_) => {
            log::error!("the kernel finished running? this shouldnt happen");
            Status::LOAD_ERROR
        }
        Err(e) => {
            error!("{}", e);
            uefi::boot::stall(Duration::from_secs(10));
            Status::LOAD_ERROR
        }
    }
}

fn await_press_enter() {
    let _ =
        uefi::system::with_stdout(|output| output.write_str("Press enter to start the kernel!"));
    uefi::system::with_stdin(|input| {
        loop {
            if let Some(key) = input.read_key().unwrap() {
                match key {
                    Key::Printable(ch) => {
                        if char::from(ch) == '\r' {
                            break;
                        }
                    }
                    Key::Special(_) => {}
                }
            }
        }
    });
}

fn boot_kernel() -> Result<(), String> {
    let kernel_path = kernel_device_path(LINUX_PATH)?;
    let loaded_kernel = uefi::boot::load_image(
        uefi::boot::image_handle(),
        LoadImageSource::FromDevicePath {
            device_path: &kernel_path,
            boot_policy: uefi::proto::BootPolicy::BootSelection,
        },
    )
    .map_err(|e| format!("Failed to load kernel image: {e:?}"))?;
    set_cmdline(loaded_kernel, CMDLINE)?;

    let (initrd_ptr, initrd_size) = read_file_to_persistent_buffer(INITRD_PATH)?;
    let initrd_phys = initrd_ptr.as_ptr() as u64;

    let initrd_info_ptr = unsafe {
        let ptr = uefi::boot::allocate_pool(
            uefi::boot::MemoryType::LOADER_DATA,
            core::mem::size_of::<InitrdInfo>(),
        )
        .map_err(|e| format!("Failed to allocate initrd info: {e:?}"))?;
        let info_ptr = ptr.as_ptr() as *mut InitrdInfo;
        info_ptr.write(InitrdInfo {
            base: initrd_phys,
            size: initrd_size as u64,
        });
        info_ptr
    };

    unsafe {
        uefi::boot::install_configuration_table(
            &LINUX_EFI_INITRD_MEDIA_GUID,
            initrd_info_ptr as *const _,
        )
        .map_err(|e| format!("Failed to install initrd config table: {e:?}"))?;
    }

    uefi::boot::start_image(loaded_kernel).map_err(|e| format!("Failed to start kernel: {e:?}"))
}
fn read_file_to_persistent_buffer(path: &CStr16) -> Result<(NonNull<u8>, usize), String> {
    let temp_data = {
        let mut fs = get_image_file_system(uefi::boot::image_handle())
            .map_err(|e| format!("failed to get filesystem: {e:?}"))?;
        let mut volume = fs
            .open_volume()
            .map_err(|e| format!("failed to open volume: {e:?}"))?;

        let mut file_handle = volume
            .open(path, FileMode::Read, FileAttribute::empty())
            .map_err(|e| format!("failed to open {path}: {e:?}"))?
            .into_regular_file()
            .ok_or_else(|| format!("{path} is not a regular file"))?;

        let file_info = file_handle
            .get_boxed_info::<FileInfo>()
            .map_err(|e| format!("failed to get file info: {e:?}"))?;
        let size = file_info.file_size() as usize;

        let mut buf = vec![0; size];
        let written = file_handle
            .read(&mut buf)
            .map_err(|e| format!("failed to read {path}: {e:?}"))?;
        if written != size {
            return Err(format!(
                "read incorrect size: expected {}, got {}",
                size, written
            ));
        }
        buf
    };

    let size = temp_data.len();
    let pages = (size + boot::PAGE_SIZE - 1) / boot::PAGE_SIZE;
    let initrd_alloc_ptr = uefi::boot::allocate_pages(
        uefi::boot::AllocateType::AnyPages,
        uefi::boot::MemoryType::RUNTIME_SERVICES_DATA,
        pages,
    )
    .map_err(|e| format!("Failed to allocate persistent memory: {e:?}"))?;
    log::error!(
        "initrd pointer: {:?}, PAGE_SIZE: {}",
        initrd_alloc_ptr.as_ptr() as *mut u8,
        boot::PAGE_SIZE
    );

    unsafe {
        core::ptr::copy_nonoverlapping(temp_data.as_ptr(), initrd_alloc_ptr.as_ptr(), size);
    }
    Ok((initrd_alloc_ptr, size))
}

fn get_blob(blob_path: &CStr16) -> Result<Vec<u8>, String> {
    let mut fs = get_image_file_system(uefi::boot::image_handle())
        .map_err(|e| format!("failed to get EFI partition filesystem: {e:?}"))?;
    let mut volume = fs
        .open_volume()
        .map_err(|e| format!("failed to open volume: {e:?}"))?;

    let mut file_handle = volume
        .open(blob_path, FileMode::Read, FileAttribute::empty())
        .map_err(|e| format!("failed to open {blob_path}: {e:?}"))?
        .into_regular_file()
        .ok_or_else(|| format!("{blob_path} is not a regular file"))?;

    let file_info = file_handle
        .get_boxed_info::<FileInfo>()
        .map_err(|e| format!("failed to get file info: {e:?}"))?;

    let mut buf = vec![0; file_info.file_size() as usize];
    let written = file_handle
        .read(&mut buf)
        .map_err(|e| format!("failed to read {blob_path}: {e:?}"))?;

    if written != buf.len() {
        return Err(format!(
            "read incorrect size: expected {}, got {}",
            buf.len(),
            written
        ));
    }
    Ok(buf)
}

fn kernel_device_path(path: &CStr16) -> Result<Box<DevicePath>, String> {
    let self_handle = uefi::boot::image_handle();
    let loaded_image_dp = uefi::boot::open_protocol_exclusive::<LoadedImageDevicePath>(self_handle)
        .map_err(|e| format!("failed to open LoadedImage: {e:?}"))?;

    let file_path = FilePath { path_name: path };
    let mut out = vec![MaybeUninit::new(0); file_path.size_in_bytes().unwrap() as usize];
    file_path.write_data(&mut out);
    let mut backing_buf = vec![];
    let mut builder = DevicePathBuilder::with_vec(&mut backing_buf);
    for node in loaded_image_dp.node_iter() {
        if let uefi::proto::device_path::DevicePathNodeEnum::MediaFilePath(_) =
            node.as_enum().unwrap()
        {
            builder = builder
                .push(&unsafe {
                    DevicePathNode::from_ffi_ptr(
                        out.as_ptr()
                            .cast::<uefi::proto::device_path::FfiDevicePath>(),
                    )
                })
                .unwrap();
            break;
        } else {
            builder = builder.push(&node).unwrap();
        }
    }
    let actual_dp = builder.finalize().unwrap();
    Ok(actual_dp.to_owned())
}

fn set_cmdline(image_handle: uefi::Handle, cmdline: &CStr16) -> Result<(), String> {
    let mut loaded_image = uefi::boot::open_protocol_exclusive::<LoadedImage>(image_handle)
        .map_err(|e| format!("failed to open LoadedImage on kernel: {e:?}"))?;
    unsafe {
        loaded_image.set_load_options(
            cmdline.as_ptr() as *const u8,
            cmdline.as_bytes().len() as u32,
        );
    }
    Ok(())
}
