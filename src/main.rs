use std::fs::File;
use std::io;
use std::io::Read;
use std::io::Write;
use std::os::unix::io::AsRawFd;
use std::time::Instant;

const BLKGETSIZE64: u64 = 0x80081272;
const MIN_BLOCK_SIZE: u64 = 1 * 1024 * 1024; // 1 MB
const MAX_BLOCK_SIZE: u64 = 128 * 1024 * 1024; // 128 MB

fn main() -> io::Result<()> {
    let path = "/dev/sda";
    //let path = "research/100M.bin";

    let (disk_size, sector_size) = get_size(path)?;

    println!("Disk: {}", path);
    println!("  Disk size .: {}", disk_size);
    println!("  Sector size: {}", sector_size);
    println!("");

    // figure out block size and count
    let sector_size_effective = if sector_size == 0 { 512 } else { sector_size };
    let block_size = disk_size / 1000 / sector_size_effective as u64 * sector_size_effective as u64; // divide in 1000 parts by default
    let block_size = if block_size < MIN_BLOCK_SIZE {
        MIN_BLOCK_SIZE
    } else if block_size > MAX_BLOCK_SIZE {
        MAX_BLOCK_SIZE
    } else {
        block_size
    };
    let block_count = get_block_count(disk_size, block_size);

    // per-file variable
    let mut file = File::open(path)?;
    let mut buffer_in = vec![0u8; block_size as usize];

    // go over each block
    let overall_start_time = Instant::now();
    for block_index in 0..block_count {
        let (start, end) = get_block_offset(disk_size, block_size, block_index)?;

        let to_read = (end - start + 1) as usize;
        let instant_start_time = Instant::now();
        file.read_exact(&mut buffer_in[..to_read])?;
        let instant_elapsed = instant_start_time.elapsed();
        let overall_elapsed = overall_start_time.elapsed();

        let instant_seconds = instant_elapsed.as_secs_f64();
        let instant_speed = if instant_seconds > 0.0 {
            (end - start + 1) as f64 / instant_seconds / 1024.0 / 1024.0
        } else {
            0.0
        };
        let overall_seconds = overall_elapsed.as_secs_f64();
        let overall_speed = if instant_seconds > 0.0 {
            (end + 1) as f64 / overall_seconds / 1024.0 / 1024.0
        } else {
            0.0
        };

        print!(
            "\r\x1b[2K{}% ({}-{}, {:.2} MB/s, {:.2} MB/s overall)",
            100 * (end + 1) / disk_size,
            start,
            end,
            instant_speed,
            overall_speed,
        );
        io::stdout().flush().unwrap();
    }

    Ok(())
}

fn get_block_count(disk_size: u64, block_size: u64) -> u64 {
    (disk_size + block_size - 1) / block_size
}

fn get_block_offset(disk_size: u64, block_size: u64, block_index: u64) -> io::Result<(u64, u64)> {
    let start = block_index * block_size;
    if start >= disk_size {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "Block index out of range",
        ));
    }

    let mut end = start + block_size - 1;
    if end >= disk_size {
        end = disk_size - 1;
    }

    Ok((start, end))
}

fn get_size(path: &str) -> io::Result<(u64, u32)> {
    if path.starts_with("/dev/") {
        get_disk_size(path)
    } else {
        get_file_size(path)
    }
}

fn get_disk_size(device_path: &str) -> io::Result<(u64, u32)> {
    let file = File::open(device_path)?;
    let fd = file.as_raw_fd();

    let mut disk_size: u64 = 0;
    let ret = unsafe { libc::ioctl(fd, BLKGETSIZE64, &mut disk_size) };
    if ret != 0 {
        return Err(io::Error::last_os_error());
    }

    const BLKSSZGET: u64 = 0x1268;
    let mut sector_size: u32 = 0;
    let ret = unsafe { libc::ioctl(fd, BLKSSZGET, &mut sector_size) };
    if ret != 0 {
        return Err(io::Error::last_os_error());
    }

    Ok((disk_size, sector_size))
}

fn get_file_size(file_name: &str) -> io::Result<(u64, u32)> {
    let metadata = std::fs::metadata(file_name)?;
    let file_size = metadata.len();
    Ok((file_size, 0))
}
