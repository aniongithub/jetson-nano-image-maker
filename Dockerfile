ARG BASE_IMAGE=ubuntu:20.04
FROM ${BASE_IMAGE} AS base

ARG DEBIAN_FRONTEND=noninteractive
ARG INSTALL_L4T=false
ARG SKIP_BIONIC_APT=0
# NVIDIA L4T apt repo coordinates, sourced from boards.json (board.l4t_apt).
# L4T_SOC is the SoC repo segment (e.g. t210 for Nano, t234 for Orin) and
# L4T_RELEASE is the apt release/suite (e.g. r32.6, r36.4).
ARG L4T_SOC=""
ARG L4T_RELEASE=""
# Whether to install the Docker engine + NVIDIA container runtime, and the L4T
# major (e.g. 32, 36) used to select the correct per-era container package set.
ARG INSTALL_CONTAINER_RUNTIME=false
ARG L4T_MAJOR=""

RUN apt-get update
RUN apt-get install -y ca-certificates

RUN apt-get install -y sudo
RUN apt-get install -y ssh
RUN apt-get install -y netplan.io

# resizerootfs
RUN apt-get install -y udev
RUN apt-get install -y parted

# ifconfig
RUN apt-get install -y net-tools

# needed by knod-static-nodes to create a list of static device nodes
RUN apt-get install -y kmod

# Install our resizerootfs service
COPY root/etc/systemd/ /etc/systemd

RUN systemctl enable resizerootfs
RUN systemctl enable ssh
RUN systemctl enable systemd-networkd
RUN systemctl enable setup-resolve

RUN mkdir -p /opt/nvidia/l4t-packages
RUN touch /opt/nvidia/l4t-packages/.nv-l4t-disable-boot-fw-update-in-preinstall

COPY root/etc/apt/ /etc/apt
COPY root/usr/share/keyrings /usr/share/keyrings

# Generate the NVIDIA L4T apt source from build args (driven by boards.json:
# board.l4t_apt.{soc,release}). Only emitted when installing L4T and both the
# SoC (e.g. t210, t234) and release (e.g. r32.6, r36.4) are provided. The same
# committed keyring signs every current L4T release (r32 through r36).
RUN if [ "$INSTALL_L4T" = "true" ] && [ -n "$L4T_SOC" ] && [ -n "$L4T_RELEASE" ]; then \
        { \
          echo "deb [signed-by=/usr/share/keyrings/nvidia-l4t-archive-keyring.asc] https://repo.download.nvidia.com/jetson/common ${L4T_RELEASE} main"; \
          echo "deb [signed-by=/usr/share/keyrings/nvidia-l4t-archive-keyring.asc] https://repo.download.nvidia.com/jetson/${L4T_SOC} ${L4T_RELEASE} main"; \
        } > /etc/apt/sources.list.d/nvidia-l4t.list; \
    fi

# Remove bionic apt sources for non-18.04 builds
RUN if [ "$SKIP_BIONIC_APT" = "1" ] && [ -f /etc/apt/sources.list.d/bionic.list ]; then \
        rm -f /etc/apt/sources.list.d/bionic.list; \
    fi

RUN apt-get update

# nv-l4t-usb-device-mode
RUN apt-get install -y bridge-utils

# https://docs.nvidia.com/jetson/l4t/index.html#page/Tegra%20Linux%20Driver%20Package%20Development%20Guide/updating_jetson_and_host.html
#
# The L4T r36 nvidia-l4t-initrd postinst registers a dpkg trigger that runs
# nv-update-initrd to inject the LUKS disk-encryption unlock helper
# (nvluks-srv-app) into the initramfs. That helper is supplied by the BSP via
# apply_binaries.sh, not the apt repo, so in this apt-only rootfs the trigger
# fails. We build unencrypted images and the package already ships a valid
# /boot/initrd, so neutralise nv-update-initrd for the duration of the install
# (dpkg-divert renames the package's real binary to nv-update-initrd.distrib and
# our no-op stub satisfies the trigger), then restore it afterwards. This is a
# no-op for L4T r32 (Nano), whose package ships no such trigger.
RUN if [ "$INSTALL_L4T" = "true" ] ; then \
            dpkg-divert --local --rename --add /usr/sbin/nv-update-initrd && \
            printf '#!/bin/sh\nexit 0\n' > /usr/sbin/nv-update-initrd && \
            chmod +x /usr/sbin/nv-update-initrd && \
            apt-get install -y -o Dpkg::Options::="--force-overwrite" \
                nvidia-l4t-core \
                nvidia-l4t-init \
                nvidia-l4t-bootloader \
                nvidia-l4t-camera \
                nvidia-l4t-initrd \
                nvidia-l4t-xusb-firmware \
                nvidia-l4t-kernel \
                nvidia-l4t-kernel-dtbs \
                nvidia-l4t-kernel-headers \
                nvidia-l4t-cuda \
                jetson-gpio-common \
                python3-jetson-gpio && \
            rm -f /usr/sbin/nv-update-initrd && \
            dpkg-divert --local --rename --remove /usr/sbin/nv-update-initrd ; \
        else \
            echo "Skipping NVIDIA L4T package installation (INSTALL_L4T=${INSTALL_L4T})" ; \
        fi

RUN rm -rf /opt/nvidia/l4t-packages

# Optionally install the Docker engine (from Ubuntu) plus the NVIDIA container
# runtime (from the L4T apt repo configured above), and set Docker's default
# runtime to nvidia so `docker build`/`run` see the GPU by default — matching
# NVIDIA's own Jetson images. The package set differs by L4T era:
#   r32 (JetPack 4): docker.io + nvidia-container-toolkit + nvidia-container-runtime
#   r36 (JetPack 6): docker.io + nvidia-container-toolkit (runtime ships in -base)
# Both provide /usr/bin/nvidia-container-runtime, so one daemon.json fits both.
# A temporary policy-rc.d stops package postinsts from starting daemons inside
# the build container. Driven by boards.json (board.features.container_runtime).
RUN if [ "$INSTALL_CONTAINER_RUNTIME" = "true" ]; then \
        printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d && \
        NV_CONTAINER_PKGS="nvidia-container-toolkit" && \
        if [ "$L4T_MAJOR" = "32" ]; then NV_CONTAINER_PKGS="nvidia-container-toolkit nvidia-container-runtime"; fi && \
        apt-get install -y --no-install-recommends docker.io $NV_CONTAINER_PKGS && \
        mkdir -p /etc/docker && \
        printf '{\n  "runtimes": {\n    "nvidia": {\n      "path": "nvidia-container-runtime",\n      "runtimeArgs": []\n    }\n  },\n  "default-runtime": "nvidia"\n}\n' > /etc/docker/daemon.json && \
        systemctl enable docker && \
        rm -f /usr/sbin/policy-rc.d ; \
    else \
        echo "Skipping container runtime install (INSTALL_CONTAINER_RUNTIME=${INSTALL_CONTAINER_RUNTIME})" ; \
    fi

COPY root/ /

RUN useradd -ms /bin/bash jetson
RUN echo 'jetson:jetson' | chpasswd

RUN usermod -a -G sudo jetson

# When the container runtime is installed, let the default user drive Docker
# without sudo. No-op (guarded) for minimal images where docker isn't present.
RUN if getent group docker >/dev/null 2>&1; then usermod -a -G docker jetson; fi
