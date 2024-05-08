# Immich in LXC

Install Immich in LXC with optional CUDA support. This guide should be appliable to any bare-metal installation.

## Introduction

[Immich](https://github.com/immich-app/immich) is a

> High performance self-hosted photo and video management solution

I really like Immich and its corherent experience in both mobile and web. However, the official Documents only provides Docker installation guide, which is less than ideal for a LXC user.

But, not providing a bare-metal installation guide for immich can be justified as Immich is more than a simple binary and does requires some efforts to set up in current state.

**This guide is heavily inspired by another guide, [Immich Native](https://github.com/arter97/immich-native). KUDO to its author, arter97!** 

## Immich Components

- Immich
    - Web Server
    - Microservices
    - Machine Learning Server
- Database
    - Redis
    - Postgresql
        - PG-vector
- System
    - ffmpeg
    - Node.js
- (Optional) Reverse Proxy
    - Nginx
- (Optional) NVIDIA
    - Driver
    - CuDNN

As one could tell, it is a lot of works, and a lot of things to get right. However, Immich is quite resilience and will fall-back to a baseline default when hardware-acceleration does not work.

For the simplicity of the guide, all the components are installed in a single LXC container. However, it is always possible to run different components in different LXC containers. It is always a design choice.

## Prepare the LXC container

For LXC container, it is recommend to use Ubuntu 22.04 LTS even though a newer LTS has been released. The reason is that the CuDNN shipped with the newer release is too advanced for the current Immich Onnx GPU runtime. If one only plans to use CPU, it should not be a problem.


