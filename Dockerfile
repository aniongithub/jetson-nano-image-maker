ARG BASE_IMAGE=ubuntu:20.04
FROM ${BASE_IMAGE} AS base

ARG DEBIAN_FRONTEND=noninteractive
ARG INSTALL_L4T=false
ARG SKIP_BIONIC_APT=0

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

# Remove bionic apt sources for non-18.04 builds
RUN if [ "$SKIP_BIONIC_APT" = "1" ] && [ -f /etc/apt/sources.list.d/bionic.list ]; then \
        rm -f /etc/apt/sources.list.d/bionic.list; \
    fi

RUN apt-get update

# nv-l4t-usb-device-mode
RUN apt-get install -y bridge-utils

# https://docs.nvidia.com/jetson/l4t/index.html#page/Tegra%20Linux%20Driver%20Package%20Development%20Guide/updating_jetson_and_host.html
RUN if [ "$INSTALL_L4T" = "true" ] ; then \
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
                python3-jetson-gpio ; \
        else \
            echo "Skipping NVIDIA L4T package installation (INSTALL_L4T=${INSTALL_L4T})" ; \
        fi

RUN rm -rf /opt/nvidia/l4t-packages

COPY root/ /

RUN useradd -ms /bin/bash jetson
RUN echo 'jetson:jetson' | chpasswd

RUN usermod -a -G sudo jetson
