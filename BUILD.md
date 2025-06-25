## Build Instructions


### Prerequisites

This application is built using rust and thus it requires  you to have [Rust](https://www.rust-lang.org/tools/install) installed.
You can install Rust using [rustup](https://rustup.rs/):

~~~sh
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
~~~

After installing Rust, ensure that `cargo` is available in your PATH.

In addition, you might need to add build targets:

~~~sh
rustup target add x86_64-unknown-linux-gnu
rustup target add x86_64-unknown-linux-musl
~~~


### Build

~~~sh
make release
~~~
