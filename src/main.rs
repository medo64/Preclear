use aes::Aes128;
use aes::{cipher::KeyInit, cipher::generic_array::GenericArray};
use colored::*;
use rand::RngCore;
use std::env;
use std::fs::File;
use std::io;
use std::io::Read;
use std::io::Write;
use std::os::unix::io::AsRawFd;
use std::time::Instant;
use xts_mode::{Xts128, get_tweak_default};

mod ioctl;

const MIN_BLOCK_SIZE: u64 = 1 * 1024 * 1024; // 1 MB
const MAX_BLOCK_SIZE: u64 = 128 * 1024 * 1024; // 128 MB

fn main() -> io::Result<()> {
    let mut arg_key: Option<String> = None;
    let mut arg_verbose = false;
    let mut arg_write_random = false;
    let mut arg_write_zero = false;
    let mut arg_start_at = 0u64;
    let mut arg_block_size = 0u64;
    let mut arg_path: Option<String> = None;

    let args: Vec<String> = env::args().collect();
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "-b" => {
                if i + 1 < args.len() {
                    arg_block_size = args[i + 1].parse::<u64>().unwrap_or_else(|_| {
                        eprintln!(
                            "{}",
                            "Error: block size requires a valid integer argument!".bright_red()
                        );
                        std::process::exit(1);
                    });
                    if arg_block_size < 16 {
                        eprintln!(
                            "{}",
                            "Error: block size must be equal or larger than 16 bytes!".bright_red()
                        );
                        std::process::exit(1);
                    } else if arg_block_size % 16 != 0 {
                        eprintln!(
                            "{}",
                            "Error: block size must be a multiple of 16!".bright_red()
                        );
                        std::process::exit(1);
                    }
                    i += 1;
                } else {
                    eprintln!("{}", "Error: block size requires an argument!".bright_red());
                    std::process::exit(1);
                }
            }
            "-h" => {
                eprintln!("preclear [-b <blocksize>] [-k <key>] [-s <position>] [-w] path");
                eprintln!();
                eprintln!("  -b <blocksize>: specifies block size; usually not needed");
                eprintln!("  -k <key>:       specifies key; usually not needed");
                eprintln!("  -s <position:   position at which to start check; default is start");
                eprintln!("  -w:             if set, disk will be filled with random data");
                eprintln!("  path:           device path");
                eprintln!();
                eprintln!("EXAMPLES");
                eprintln!("  read/write test: preclear -w /dev/sdz");
                eprintln!("  read-only test:  preclear /dev/sdz");
                std::process::exit(1);
            }
            "-k" => {
                if i + 1 < args.len() {
                    arg_key = Some(args[i + 1].clone());
                    i += 1;
                } else {
                    eprintln!("{}", "Error: key requires an argument!".bright_red());
                    std::process::exit(1);
                }
            }
            "-s" => {
                if i + 1 < args.len() {
                    arg_start_at = args[i + 1].parse::<u64>().unwrap_or_else(|_| {
                        eprintln!(
                            "{}",
                            "Error: start position requires a valid integer argument!".bright_red()
                        );
                        std::process::exit(1);
                    });
                    i += 1;
                } else {
                    eprintln!(
                        "{}",
                        "Error: start position requires an argument!".bright_red()
                    );
                    std::process::exit(1);
                }
            }
            "-v" => {
                arg_verbose = true;
            }
            "-w" => {
                arg_write_random = true;
            }
            "-z" => {
                arg_write_zero = true;
            }
            _ => {
                if arg_path.is_some() {
                    eprintln!(
                        "{}",
                        "Error: only one file allowed as an argument!".bright_red()
                    );
                }
                arg_path = Some(args[i].clone());
            }
        }
        i += 1;
    }

    if arg_write_random && arg_write_zero {
        eprintln!(
            "{}",
            "Error: cannot write both zero (-z) and random (-w)!".bright_red()
        );
    }
    let arg_write = arg_write_random || arg_write_zero;

    let arg_key_binary = if let Some(ref key_str) = arg_key {
        let key_str_clean: String = key_str.chars().filter(|c| *c != '-').collect();
        let key_bytes = match hex::decode(&key_str_clean) {
            Ok(bytes) => bytes,
            Err(e) => {
                eprintln!("{}", format!("Error parsing hex key: {}!", e).bright_red());
                std::process::exit(1);
            }
        };
        if key_bytes.len() != 32 {
            eprintln!("{}", "Key must be 64 hex characters!".bright_red());
            std::process::exit(1);
        }
        Some(key_bytes)
    } else {
        None
    };

    if arg_path.is_none() {
        eprintln!("{}", "Error: no file configured!".bright_red());
    }

    //let path = "/dev/sda";
    let path = arg_path.unwrap();
    let (disk_size, sector_size) = get_size(&path)?;

    println!("Disk: {}", path.bright_cyan());
    println!("  Disk size .: {}", format!("{}", disk_size).bright_cyan());
    println!(
        "  Sector size: {}",
        format!("{}", sector_size).bright_cyan()
    );
    println!();

    // figure out block size and count
    let sector_size_effective = if sector_size == 0 { 512 } else { sector_size };
    let block_size = if arg_block_size > 0 {
        arg_block_size
    } else {
        let block_size_init =
            disk_size / 1000 / sector_size_effective as u64 * sector_size_effective as u64; // divide in 1000 parts by default
        if block_size_init < MIN_BLOCK_SIZE {
            MIN_BLOCK_SIZE
        } else if block_size_init > MAX_BLOCK_SIZE {
            MAX_BLOCK_SIZE
        } else {
            block_size_init
        }
    };
    let block_count = get_block_count(disk_size, block_size);

    // verbose details
    if arg_verbose {
        println!(
            "  Block count: {}",
            format!("{}", block_count).bright_cyan()
        );
        println!("  Block size : {}", format!("{}", block_size).bright_cyan());
        if !arg_write {
            println!(); // extra spacing since key is not displayed
        }
    }

    // adjust start index
    if arg_start_at >= disk_size {
        eprintln!("{}", "Error: start_at is beyond disk size!".bright_red());
        std::process::exit(1);
    }
    let start_block = arg_start_at / block_size;
    if start_block > 0 {
        println!(
            "  Start at ..: {}",
            format!("{}", start_block * block_size).bright_yellow()
        );
    }

    // generate random key
    let mut key = [0u8; 32]; // 2 * 128 bits for XTS
    if let Some(ref key_bytes) = arg_key_binary {
        key.copy_from_slice(&key_bytes[..]);
    } else {
        rand::rng().fill_bytes(&mut key);
    }
    if arg_write {
        // key is only important if write is enabled
        print!("  Key .......: ");
        for (i, byte) in key.iter().enumerate() {
            if i > 0 && i % 4 == 0 {
                print!("{}", "-".bright_cyan());
            }
            if arg_key.is_some() {
                print!("{}", format!("{:02x}", byte).bright_yellow());
            } else {
                print!("{}", format!("{:02x}", byte).bright_cyan());
            }
        }
        println!();
        println!();
    }

    // setup XTS (//https://docs.rs/xts-mode/latest/xts_mode/)
    let cipher_1 = Aes128::new(GenericArray::from_slice(&key[..16]));
    let cipher_2 = Aes128::new(GenericArray::from_slice(&key[16..]));
    let xts = Xts128::<Aes128>::new(cipher_1, cipher_2);

    // write bytes
    if arg_write {
        let mut file = File::options().read(true).write(arg_write).open(&path)?;

        // write each block
        let overall_start_time = Instant::now();
        for block_index in start_block..block_count {
            let (start, end) = get_block_offset(disk_size, block_size, block_index)?;

            let mut buffer_write = vec![0u8; block_size as usize];
            if arg_write_random {
                xts.encrypt_area(&mut buffer_write, block_size as usize, 0, get_tweak_default);
            }

            let to_write = (end - start + 1) as usize;
            let instant_start_time = Instant::now();
            file.write_all(&buffer_write[..to_write])?;
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
                "\r\x1b[2K{}% (wrote {} bytes at {:.2} MB/s, {:.2} MB/s overall)",
                100 * (end + 1) / disk_size,
                end + 1,
                instant_speed,
                overall_speed,
            );
            io::stdout().flush().unwrap();
        }

        println!();
    }

    // go over each block
    let mut file = File::open(&path)?;
    let mut buffer_data = vec![0u8; block_size as usize];
    let overall_start_time = Instant::now();
    for block_index in start_block..block_count {
        let (start, end) = get_block_offset(disk_size, block_size, block_index)?;

        let to_read = (end - start + 1) as usize;
        let instant_start_time = Instant::now();
        file.read_exact(&mut buffer_data[..to_read])?;
        let instant_elapsed = instant_start_time.elapsed();
        let overall_elapsed = overall_start_time.elapsed();

        let instant_seconds = instant_elapsed.as_secs_f64();
        let instant_speed = if instant_seconds > 0.0 {
            (end - start + 1) as f64 / instant_seconds / 1024.0 / 1024.0
        } else {
            0.0
        };

        if arg_write {
            if arg_write_random {
                xts.decrypt_area(&mut buffer_data, block_size as usize, 0, get_tweak_default);
            }
            for (i, &b) in buffer_data[..to_read].iter().enumerate() {
                if b != 0 {
                    eprintln!(
                        "{}",
                        format!("Validation failed at byte offset {}!", start + i as u64)
                            .bright_red()
                    );
                    std::process::exit(2);
                }
            }
        }

        let overall_seconds = overall_elapsed.as_secs_f64();
        let overall_speed = if instant_seconds > 0.0 {
            (end + 1) as f64 / overall_seconds / 1024.0 / 1024.0
        } else {
            0.0
        };

        print!(
            "\r\x1b[2K{}% (read {} bytes at {:.2} MB/s, {:.2} MB/s overall)",
            100 * (end + 1) / disk_size,
            end + 1,
            instant_speed,
            overall_speed,
        );
        io::stdout().flush().unwrap();
    }

    println!();
    println!();
    if arg_write_random {
        println!(
            "{}",
            "Read/write test was completed successfully".bright_green()
        );
    } else if arg_write_zero {
        println!(
            "{}",
            "Cleaning disk was completed successfully".bright_green()
        );
    } else {
        println!("{}", "Read test was completed successfully".bright_green());
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

    let disk_size: u64 = ioctl::get_device_size_in_bytes(fd)?;
    let sector_size: u32 = ioctl::get_logical_sector_size(fd)?;

    Ok((disk_size, sector_size))
}

fn get_file_size(file_name: &str) -> io::Result<(u64, u32)> {
    let metadata = std::fs::metadata(file_name)?;
    let file_size = metadata.len();
    Ok((file_size, 0))
}
