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
    - git
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

### NVIDIA go-brrrrrrrrrrr (NVIDIA GPU LXC pass-through) (Optional)

In this part of the guide, I will cover how to pass through nVidia GPU to the LXC container.

If we oversimplify things a little bit, everything is a file in Linux. Thus, the principle of this part is quite similar to the (last part)[Mount host volume to LXC container (Optional)]. We mount the nVidia "device file" into the LXC and install the driver.

First, we need to get the nVidia "device file" in the host. By default, Linux use nouveau driver for nVidia. It is a great project, but it does not support CUDA program or CuDNN in this case. (Maybe NVK driver will in one day, hopefully.) So, the "device files" that are available to us are from nouveau driver, and are not what we want. And we need to install nVidia proprietary driver (Sad face). 

Because we eventually need to have two nVidia driver running in both host and container, we do not want the package manager of the host or the container OS update the driver by themselves. Thus, we are going to use the universal `.run` file from nVidia download center.

You can copy the link by right click the download.

Inside the host machine,

```bash
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/550.78/NVIDIA-Linux-x86_64-550.78.run
chmod +x NVIDIA-Linux-x86_64-550.78.run
./NVIDIA-Linux-x86_64-550.78.run
```

Note:

- If your download failed and you start download again, the file will be named og name.1 and so on.
- Please check compatible driver version with your installed GPU. The link above is only an example.
- This method requires a driver reinstallation for every kernel update.

After the installation, proceed with a reboot of the host.

After the reboot, when running `nvidia-smi` there should be a tui output.

Now, let's set up the permission and mount the GPU.

First, let's look at the permission of the usage of GPU in the host machine.

```bash
ls -l /dev/nvidia*
ls -l /dev/dri/
```

The output will be something like this.

```bash
crw-rw-rw- 1 root root 195,   0 May  3 22:34 /dev/nvidia0
crw-rw-rw- 1 root root 195, 255 May  3 22:34 /dev/nvidiactl
crw-rw-rw- 1 root root 195, 254 May  3 22:34 /dev/nvidia-modeset
crw-rw-rw- 1 root root 508,   0 May  3 22:34 /dev/nvidia-uvm
crw-rw-rw- 1 root root 508,   1 May  3 22:34 /dev/nvidia-uvm-tools

/dev/nvidia-caps:
total 0
cr-------- 1 root root 511, 1 May  3 22:34 nvidia-cap1
cr--r--r-- 1 root root 511, 2 May  3 22:34 nvidia-cap2

total 0
drwxr-xr-x 2 root root      60 May  3 22:34 by-path
crw-rw---- 1 root video 226, 0 May  1 23:34 card0
```


Take a note of numbers, `60, 195, 226, 255, 254, 508, 511`. Note that these number may be different on different system, even different between kernel updates.

Open the `/etc/pve/<lxc-id>.conf`, add the following lines, change the numbers accordingly.

```config
# ... Existing config
lxc.cgroup2.devices.allow: c 60:* rwm
lxc.cgroup2.devices.allow: c 195:* rwm
lxc.cgroup2.devices.allow: c 226:* rwm
lxc.cgroup2.devices.allow: c 254:* rwm
lxc.cgroup2.devices.allow: c 255:* rwm
lxc.cgroup2.devices.allow: c 508:* rwm
lxc.cgroup2.devices.allow: c 511:* rwm
lxc.mount.entry: /dev/nvidia0 dev/nvidia0 none bind,optional,create=file
lxc.mount.entry: /dev/nvidiactl dev/nvidiactl none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-modeset dev/nvidia-modeset none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm dev/nvidia-uvm none bind,optional,create=file
lxc.mount.entry: /dev/nvidia-uvm-tools dev/nvidia-uvm-tools none bind,optional,create=file
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
```

After saving the config, boot the LXC container.

Inside the LXC container, install the nVidia driver but with a catch.

```bash
wget https://us.download.nvidia.com/XFree86/Linux-x86_64/550.78/NVIDIA-Linux-x86_64-550.78.run
chmod +x NVIDIA-Linux-x86_64-550.78.run
./NVIDIA-Linux-x86_64-550.78.run --no-kernel-modules
```

We install the driver without kernel modules because LXC containers shares kernel with the host machine. Because we already install the driver on the host and its kernel, and we share the kernel, we do not need the kernel modules.

Note:

- One must use the same version of nVidia driver.
- **NO KERNEL MODULES**

After all these, we should be able to run `nvidia-smi` inside the LXC without error.

For immich machine learning support, we also need to install CuDNN,

```bash
apt install cudnn
```

Zu easy, innit?

### Install utilities and databases

```bash
apt install curl git python3-venv python3-dev
```

#### Postgresql

As for postgresql, visit [official guide](https://www.postgresql.org/download/linux/ubuntu/) and install postgresql 16, as immich depends on a vector extension on version 16.

```bash
apt install -y postgresql-common
/usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
apt -y install postgresql
apt install postgresql-pgvector
```

To prepare the database, we need to make some configuration.

First, we need to become user `postgres`, and connect to the database,

```bash
su postgres
psql
```

In the psql interface, we type in following SQL command,

```SQL
CREATE DATABASE immich;
CREATE USER immich WITH ENCRYPTED PASSWORD 'A_SEHR_SAFE_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE immich to immich;
ALTER USER immich WITH SUPERUSER;
\q # To exit
```

Note: change password.

#### FFmpeg

To install ffmpeg, it is recommend not to use the ffmpeg in the Ubuntu APT repo. Instead, a static build version is recommended. Download one from [FFmpeg Static Builds](https://johnvansickle.com/ffmpeg/).

```bash
wget https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz
tar -xf ffmpeg-git-amd64-static.tar.xz
cp ffmpeg-git-amd64-static/ffmpeg /bin/ffmpeg
```

#### Redis

Immich works fine with the Redis in Ubuntu 22.04 APT repo. No additional config is needed.

```bash
apt install redis
```

#### Node.js

Immich works on Node.js 20 LTS, and Ubuntu ships an ancient node.js. We need to go to [Node.js's website](https://nodejs.org/en/download/package-manager) for the desired version.

The following script is copy-pasted from the node.js's website. One should go to the website for the latest version of the code.

```bash
# installs NVM (Node Version Manager)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# download and install Node.js
nvm install 20

# verifies the right Node.js version is in the environment
node -v # should print `v20.13.1`

# verifies the right NPM version is in the environment
npm -v # should print `10.5.2`
```

Now, we are ready to install the Immich server.

## Install Immich Server

Create a immich user, if you already done so in the above optional section, you may safely skip the following code block.

```bash
useradd -m immich
chsh immich # Optional: Change the default shell the immich user is using.
```

After creating the user, 
