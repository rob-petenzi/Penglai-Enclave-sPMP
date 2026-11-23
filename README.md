# Penglai sPMP

![Penglai header](docs/images/penglai_hdr.jpg)

Penglai is a scalable RISC-V enclave system. This repository contains the sPMP design and SDK. See the [Penglai documentation](https://penglai-doc.readthedocs.io/) and the [OSDI'21 paper](https://www.usenix.org/conference/osdi21/presentation/feng).

This repository builds Linux 6.1.32 (`linux`), OpenSBI 1.1 (`opensbi`, using the selected PMP backend), a Buildroot guest, the Penglai driver (`penglai-enclave-driver`), the `prime` enclave example (`sdk`), and QEMU (`riscv-qemu`).

From the `tee-analysis` workspace root on the host:

```sh
git submodule update --init keystone
git -C keystone submodule update --init buildroot
git -C penglai-sPMP submodule update --init --recursive sdk riscv-qemu
podman build -t tee-analysis containers/
podman run --rm -it -v "$PWD:/workspace:rw" -w /workspace/penglai-sPMP tee-analysis bash
```

Inside the container:

```sh
make run-qemu
```

`make run-qemu` builds any missing artifacts (Buildroot toolchain, Linux 6.1.32, OpenSBI 1.1, driver, SDK `prime` example, `rootfs.ext2`, and QEMU) under `build/` and launches QEMU. Override guest resources with `make run-qemu MEMORY=4G CPUS=4`, or build without booting via `make build`.

Log in as `root` with password `penglai`, then load the driver and run the example:

```sh
modprobe penglai
cd /usr/share/penglai/spmp && ./host ./prime
```

Penglai sPMP is distributed under the Mulan Permissive Software License, Version 1.
