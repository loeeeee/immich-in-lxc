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

## Host setup

I am using `Proxmox VE 8` as the LXC host. It is based on `Debian`, and I have a NVIDIA GPU, including NVIDIA proprietary driver (550) installed. 

## Prepare the LXC container

For LXC container, it is recommend to use `Ubuntu 22.04 LTS` even though a newer LTS has been released. The reason is that the CuDNN shipped with the newer release is too advanced for the current Onnx GPU runtime, which machine learning component depends on (As for Immich Version 102.3). If one only plans to use CPU, it should not be a problem.

First, create a LXC normally. Make sure there is reasonable amount CPU and memory. Because we are going to install and compile a lot of things, it would not hurt to give it a bit more. For a CPU-only Immich server, there should be at least 8 GiB of storage, and a NVIDIA GPU one should have at least 16 GiB. Also, there is no need for a privileged container, if one does not plan to mount file system directly inside the LXC container.

### Mount host volume to LXC container (Optional)

This part of the guide is about mounting a directory from the host to a unprivileged container. The directory can be a SMB or a NFS share that is already mounted on the host, or any other local directory, as long as they have proper permission set.

Edit `/etc/pve/lxc/<lxc-id>.conf` with your favorite editor. Mine is `nano`, BTW.

Add something like following example,

```config
mp0: /mnt/DigitalMemory/,mp=/mnt/DigiMem
mp1: /<path on the host>/,mp=/<path in the container>
```

Note: Do not put a space after the comma, it breaks the config file.

Now, let's set up the directory permission on the host machine.

First, some background knowledge. An unprivileged LXC container runs as a normal user with a unprivileged user id in the host machine (Let's refer to this normal user as the agent user, and the group that normal user is in as the agent group). A privileged container will have its root user has the same user id as the host root user, which makes it considered less secure. In our case, we are using a unprivileged container, and what we need to do is to **allow the agent group to access the desired directory in the host machine**. Luckily, we can predict the agent group's id based on its id in the container.

The formula is as follow,

$\text{GroupID}_{agent} = \text{GroupID}_{container} - 100000$

If we would like to have the group with id 12345 to access the directory on the host, we need to give access permission to group with id of 912345 in the host.

So, in the host machine, 

```bash
groupadd -g 912345 lxc_shares
```

In the container,

```bash
groupadd -g 12345 lxc_shares
```

Note the name of the group does not need to be the same in host and container, but to make one's life easier in the future, it is good to keep them the same.

Now, let's set up the permission of the directory in the host.

```bash
chown -R root:lxc_shares /mnt/DigitalMemory
```

To validate if it is successfully set in the host, one need to make sure that a user that is not the owner (in this case, `root`), but inside the `lxc_shares` group, can properly access the directory.

```bash
useradd foo
usermod -aG lxc_shares foo
# ...Test the access, like creating and deleting files.
userdel foo
```

If all good, we can proceed to the next step.

Inside the LXC container,

```bash
useradd -m immich
groupadd -g 12345 lxc_shares
usermod -aG lxc_shares immich
```

After, `su immich`, one should be able to access the mounted directory at `/mnt/DigiMem`.

Note: If you do not like the default `/bin/sh` shell for the new user, as the root, you can do,

```bash
chsh immich
# Then typing /bin/bash or whatever shell you like
```

And, that is it, EZ, right?

Let's move on the next part.

