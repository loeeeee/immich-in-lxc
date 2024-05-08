# Immich in LXC

Install Immich in LXC with optional CUDA support

## Introduction

[Immich](https://github.com/immich-app/immich) is a

> High performance self-hosted photo and video management solution

However, the official Documents only provides Docker installation method, which is less than ideal for a LXC user.

But, not providing a bare-metal installation guide for immich can be justified as the Immich is more than a simple binary and does requires some efforts to set up in current state.

## Immich Components

- Immich
    - Web Server
    - Microservices
    - Machine Learning Server
- Database
    - Redis
    - Postgresql
- System
    - ffmpeg
- (Optional) Reverse Proxy
    - Nginx
- (Optional) NVIDIA
    - Driver
    - CuDNN

As one could tell, it is a lot of works, and a lot of things to get right. However, Immich is quite resilience and will fall-back to a baseline default when hardware-acceleration does not work.

## Prepare LXC
