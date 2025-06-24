use std::io;

const BLKGETSIZE64: u64 = 0x80081272;
const BLKSSZGET: u64 = 0x1268;

#[cfg(not(all(target_arch = "x86_64", target_env = "musl")))]
pub fn get_device_size_in_bytes(fd: i32) -> io::Result<u64> {
    let mut device_size: u64 = 0;

    let ret = unsafe { libc::ioctl(fd, BLKGETSIZE64, &mut device_size) };
    if ret != 0 {
        return Err(io::Error::last_os_error());
    }

    Ok(device_size)
}

#[cfg(not(all(target_arch = "x86_64", target_env = "musl")))]
pub fn get_logical_sector_size(fd: i32) -> io::Result<u32> {
    let mut sector_size: u32 = 0;

    let ret = unsafe { libc::ioctl(fd, BLKSSZGET, &mut sector_size) };
    if ret != 0 {
        return Err(io::Error::last_os_error());
    }

    Ok(sector_size)
}

#[cfg(all(target_arch = "x86_64", target_env = "musl"))]
pub fn get_device_size_in_bytes(fd: i32) -> io::Result<u64> {
    let mut device_size: u64 = 0;

    let ret = unsafe { libc::ioctl(fd, BLKGETSIZE64 as i32, &mut device_size) };
    if ret != 0 {
        return Err(io::Error::last_os_error());
    }

    Ok(device_size)
}

#[cfg(all(target_arch = "x86_64", target_env = "musl"))]
pub fn get_logical_sector_size(fd: i32) -> io::Result<u32> {
    let mut sector_size: u32 = 0;

    let ret = unsafe { libc::ioctl(fd, BLKSSZGET as i32, &mut sector_size) };
    if ret != 0 {
        return Err(io::Error::last_os_error());
    }

    Ok(sector_size)
}
