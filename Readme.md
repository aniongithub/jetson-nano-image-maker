# Jetson Nano Image

> **tl;dr;** Minimal, ready-to-use Jetson images created using Docker and Github Actions.

## Problem

Nvidia privides a set of docs, scripts, and guides from their [linux-for-tegra](https://developer.nvidia.com/embedded/jetson-linux-r341) environment but initial setup always seems to require connecting to a running image via local or network means and interactively configuring things. This is impractical and un-necessary. 

## Solution

This repository uses the excellent work done by [pythops](https://github.com/pythops/jetson-nano-image) and [defunctzombie](https://github.com/defunctzombie/jetson-nano-image-maker) and uses Github Actions to automatically build a flash-ready, minimal Ubuntu image. For details on how this works, see [here](https://github.com/defunctzombie/jetson-nano-image-maker).

You can download the latest minimal images [here](https://github.com/aniongithub/jetson-nano-image-maker/releases/latest). Once downloaded and extracted, you can use [Balena Etcher](https://www.balena.io/etcher) or [Raspberry Pi Imager](https://www.raspberrypi.com/software/#:~:text=Install%20Raspberry%20Pi%20OS%20using%20Raspberry%C2%A0Pi%C2%A0Imager) to can flash the image to an sd card.

## Customizing

This repository differs from [defunctzombie/jetson-nano-image-maker](https://github.com/defunctzombie/jetson-nano-image-maker) in that it isn't meant to directly customize your image for various reasons.

If you would like to customize the image and distribute it to multiple people, you can use my other repository, jetson-bootstrap - that lets you modify this minimal image using chroot and a [Dockerfile-like syntax](https://github.com/defunctzombie/jetson-nano-image-maker) locally or directly in the cloud using Github Actions. What's more, jetson-bootstrap also comes with several modules that make it easy to add common functionality like Wi-Fi, Docker + Docker/Kubernetes and more.You can make your own images by forking this repo and modifying the `Dockerfile`. Your fork will automatically run the forked Github Actions and you'll end up with ready-to-flash images from your changes.

## Credentials

The default credentials:

username: `jetson`
password: `jetson`

## References

### Additional links

- https://github.com/pythops/jetson-nano-image
- https://github.com/defunctzombie/jetson-nano-image-maker
- https://developer.nvidia.com/embedded/linux-tegra
- https://docs.nvidia.com/jetson/l4t/index.html#page/Tegra%20Linux%20Driver%20Package%20Development%20Guide/updating_jetson_and_host.html
- https://docs.nvidia.com/jetson/l4t/index.html#page/Tegra%20Linux%20Driver%20Package%20Development%20Guide/flashing.html#wwpID0E0CM0HA

## License

MIT
