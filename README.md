Preclear
========

Small utility allowing for reading and writing of every byte on a disk for verification purposes.


## Usage

### Synopsis

    preclear [OPTION] device


### Options

Reads and (optionally) writes bytes to disk in order to find any errors.

* `-b <size>`: Block size to use for read/write operation
* `-k <key>`: Key to use to generate random data for write
* `-s <byte>`: Byte to start operation at
* `-w`: Before reading, fill disk with random data
* `-v`: More details


### Examples

Write and verify (recommended, but destructible):

    preclear -w /dev/sda


Just read the whole disk:

    preclear /dev/sda


Continue operation that was interrupted:

    preclear -k <old_key> -s <byte_index> /dev/sda


### Notes

#### Write verification

For write operation, a random key (or specified key) is used to generate AES128 stream.
That stream is indistinguishable from random data and thus it can be used to both verify disk doesn't lie about capacity and to randomize its content (e.g. if it's going to be encrypted lated).
Once all blocks are written, read operation compares content it reads with data it has written.


#### Block size

Block size for read/write operations is automatically deduced based on disk size.
It can range from 1 to 128 MB.
