FROM ubuntu:22.04 AS unzip

RUN apt update && apt install -y xz-utils bzip2

# UNUSED :(
# COPY qemu-2k1000-static.20240526.tar.xz /
# ADD https://github.com/LoongsonLab/2k1000-materials/releases/download/qemu-static-20240526/qemu-static-20240526.tar.xz /
# RUN cd /tmp && tar xavf /qemu-2k1000-static.20240526.tar.xz

# UNUSED :(
# COPY qemu-prebuilt-7.0.0.tar.gz /qemu.tar.gz
# TODO
# RUN mkdir /qemu && cd /qemu && tar xavf /qemu.tar.gz

# USED !
# COPY riscv64--musl--bleeding-edge-2020.08-1.tar.bz2 /
ADD --checksum=sha256:2af03e220070eacf6eaf63ccb7442ca5af805caf96ae52fb3eb15370988f12cf https://toolchains.bootlin.com/downloads/releases/toolchains/riscv64/tarballs/riscv64--musl--bleeding-edge-2020.08-1.tar.bz2 /
RUN cd /opt && tar jxvf /riscv64--musl--bleeding-edge-2020.08-1.tar.bz2

# USED ? cloned into /opt but not shown on https://github.com/oscomp/testsuits-for-oskernel/tree/pre-2025/
# COPY toolchain-loongarch64-linux-gnu-gcc8-host-x86_64-2022-07-18.tar.xz /
# TODO
# RUN cd /opt/ && tar xavf /toolchain-loongarch64-linux-gnu-gcc8-host-x86_64-2022-07-18.tar.xz

# USED !
# COPY gcc-13.2.0-loongarch64-linux-gnu.tgz /
ADD https://github.com/LoongsonLab/oscomp-toolchains-for-oskernel/releases/download/gcc-13.2.0-loongarch64/gcc-13.2.0-loongarch64-linux-gnu.tgz /
RUN cd /opt/ && tar xavf /gcc-13.2.0-loongarch64-linux-gnu.tgz

# USED !
# COPY loongarch64-linux-musl-cross.tgz /
ADD https://github.com/LoongsonLab/oscomp-toolchains-for-oskernel/releases/download/loongarch64-linux-musl-cross-gcc-13.2.0/loongarch64-linux-musl-cross.tgz /
RUN cd /opt/ && tar xavf /loongarch64-linux-musl-cross.tgz

# USED !
# COPY riscv64-linux-musl-cross.tgz /
ADD https://musl.cc/riscv64-linux-musl-cross.tgz /
RUN cd /opt/ && tar xavf /riscv64-linux-musl-cross.tgz

# USED !
# COPY kendryte-toolchain.tar.gz /
ADD https://github.com/kendryte/kendryte-gnu-toolchain/releases/download/v8.2.0-20190213/kendryte-toolchain-ubuntu-amd64-8.2.0-20190213.tar.gz /
RUN cd /opt/ && tar xavf /kendryte-toolchain-ubuntu-amd64-8.2.0-20190213.tar.gz

# USED !
# ==> QEMU
FROM ubuntu:22.04 AS qemu

RUN apt update
RUN apt install -y --no-install-recommends xz-utils git python3 python3-pip python3-venv build-essential ninja-build pkg-config libglib2.0-dev libpixman-1-dev libslirp-dev gnupg
RUN python3 -m pip install tomli
ADD https://download.qemu.org/qemu-9.2.1.tar.xz .
ADD https://download.qemu.org/qemu-9.2.1.tar.xz.sig .
RUN gpg --keyserver hkp://keyserver.ubuntu.com --recv-keys 0x3353C9CEF108B584
RUN gpg --status-fd 1 --verify qemu-9.2.1.tar.xz.sig qemu-9.2.1.tar.xz 2>&1 | grep -q "GOODSIG 3353C9CEF108B584" || exit 1
RUN tar xf qemu-9.2.1.tar.xz \
    && cd qemu-9.2.1 \
    && ./configure --prefix=/qemu-bin-9.2.1 \
        --target-list=loongarch64-softmmu,riscv64-softmmu,aarch64-softmmu,x86_64-softmmu \
        --enable-gcov --enable-debug --enable-slirp \
    && make -j$(nproc) \
    && make install
RUN rm -rf qemu-9.2.1 qemu-9.2.1.tar.xz qemu-9.2.1.tar.xz.sig
# <== QEMU

# FINAL
FROM ubuntu:22.04

# ==> ENV
USER root
RUN apt update && apt install -y wget 

ARG DEBIAN_FRONTEND noninteractive
ENV TZ=Aisa/Shanghai
RUN echo deb http://apt.llvm.org/jammy/ llvm-toolchain-jammy-19 main >> /etc/apt/sources.list
RUN wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key | tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc

RUN apt update
RUN apt install -y --no-install-recommends git ca-certificates \
    && update-ca-certificates
RUN apt install -y --no-install-recommends \
    python3 python3-pip make curl sshpass openssh-client libc-dev
RUN apt install -y \
    git build-essential gdb-multiarch gcc-riscv64-linux-gnu \
    binutils-riscv64-linux-gnu libpixman-1-0

RUN pip install pytz Cython jwt jinja2 requests

RUN apt install --no-install-recommends -y \
    libguestfs-tools qemu-utils linux-image-generic libncurses5-dev \
    autotools-dev automake texinfo \
    tini musl musl-tools musl-dev cmake libclang-19-dev

RUN apt install -y \
    fusefat libvirglrenderer-dev libsdl2-dev libgtk-3-dev

ENV LIBGUESTFS_BACKEND=direct
RUN rm -rf /var/lib/apt/lists/*
# <== ENV

# ==> RUST
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y
RUN echo 'source $HOME/.cargo/env' >> $HOME/.bashrc
RUN export PATH="$PATH:/root/.cargo/bin"

RUN rustup install nightly-2025-01-18
RUN rustup install nightly-2024-02-03
RUN rustup default nightly-2025-01-18
RUN rustup component add llvm-tools-preview
RUN rustup target add riscv64imac-unknown-none-elf
RUN rustup target add riscv64gc-unknown-none-elf
RUN rustup target add loongarch64-unknown-linux-gnu
RUN rustup target add loongarch64-unknown-none

RUN rustup target add riscv64imac-unknown-none-elf --toolchain nightly-2025-01-18
RUN rustup target add riscv64gc-unknown-none-elf --toolchain nightly-2025-01-18
RUN rustup target add loongarch64-unknown-linux-gnu --toolchain nightly-2025-01-18
RUN rustup component add llvm-tools-preview --toolchain nightly-2025-01-18

RUN rustup target add riscv64imac-unknown-none-elf --toolchain nightly-2024-02-03
RUN rustup target add riscv64gc-unknown-none-elf --toolchain nightly-2024-02-03
RUN rustup target add loongarch64-unknown-linux-gnu --toolchain nightly-2024-02-03
RUN rustup component add llvm-tools-preview --toolchain nightly-2024-02-03

RUN cargo +nightly-2024-02-03 install cargo-binutils --locked
RUN cargo +nightly-2025-01-18 install cargo-binutils
# <== RUST

# ==> COPYING
# !!! NOTICE MODIFIED !!! COPY kendryte-toolchain /opt/kendryte-toolchain
COPY --from=unzip /opt/kendryte-toolchain /opt/kendryte-toolchain
ENV LD_LIBRARY_PATH=/opt/kendryte-toolchain/bin/:$LD_LIBRARY_PATH

# !!! NOTICE NOT INCLUDED !!!
# COPY --from=unzip /opt/toolchain-loongarch64-linux-gnu-gcc8-host-x86_64-2022-07-18 /opt/toolchain-loongarch64-linux-gnu-gcc8-host-x86_64-2022-07-18
# ENV PATH=/opt/toolchain-loongarch64-linux-gnu-gcc8-host-x86_64-2022-07-18/bin/:$PATH

COPY --from=unzip /opt/riscv64--musl--bleeding-edge-2020.08-1 /opt/riscv64--musl--bleeding-edge-2020.08-1
ENV PATH=$PATH:/opt/riscv64--musl--bleeding-edge-2020.08-1/bin

COPY --from=unzip /opt/gcc-13.2.0-loongarch64-linux-gnu /opt/gcc-13.2.0-loongarch64-linux-gnu
ENV PATH=/opt/gcc-13.2.0-loongarch64-linux-gnu/bin/:$PATH

COPY --from=unzip /opt/loongarch64-linux-musl-cross /opt/loongarch64-linux-musl-cross
ENV PATH=/opt/loongarch64-linux-musl-cross/bin:$PATH

COPY --from=unzip /opt/riscv64-linux-musl-cross /opt/riscv64-linux-musl-cross
ENV PATH=/opt/riscv64-linux-musl-cross/bin:$PATH

COPY --from=qemu /qemu-bin-9.2.1 /opt/qemu-bin-9.2.1
ENV PATH=/opt/qemu-bin-9.2.1/bin:$PATH
# <== COPYING

ENTRYPOINT ["tini", "--"]