# Immich in LXC

Install Immich in LXC with optional CUDA support. This guide should be appliable to any bare-metal installation.

## Introduction

[Immich](https://github.com/immich-app/immich) is a

> High performance self-hosted photo and video management solution

I really like Immich and its coherent experience in both mobile and web. However, the official Documents only provides Docker installation guide, which is less than ideal for a LXC user.

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
    - CuDNN (Version 8)

As one could tell, it is a lot of works, and a lot of things to get right. However, Immich is quite resilience and will fall-back to a baseline default when hardware-acceleration does not work.

For the simplicity of the guide, all the components are installed in a single LXC container. However, it is always possible to run different components in different LXC containers. It is always a design choice.

## Host setup

I am using `Proxmox VE 8` as the LXC host. It is based on `Debian`, and I have a NVIDIA GPU, including NVIDIA proprietary driver (550) installed. 

## Prepare the LXC container

For LXC container, it is recommend to use `Ubuntu 22.04 LTS` even though a newer LTS has been released. The reason is that the CuDNN shipped with the newer release is too advanced for the current Onnx GPU runtime, which machine learning component depends on (As for Immich Version 102.3). If one only plans to use CPU, it should not be a problem.

First, create a LXC normally. Make sure there is reasonable amount CPU and memory. Because we are going to install and compile a lot of things, it would not hurt to give it a bit more. For a CPU-only Immich server, there should be at least 8 GiB of storage, and a NVIDIA GPU one should have at least 16 GiB. Also, there is no need for a privileged container, if one does not plan to mount file system directly inside the LXC container.

## Mount host volume to LXC container (Optional)

This part of the guide is about mounting a directory from the host to a unprivileged container. The directory can be a SMB or a NFS share that is already mounted on the host, or any other local directory.

Follow the guide at [another repository](https://github.com/loeeeee/loe-handbook-of-gpu-in-lxc/blob/main/src/mount-host-volume.md) of mine.

And, that is it, EZ, right?

## NVIDIA go-brrrrrrrrrrr (NVIDIA GPU LXC pass-through) (Optional)

Follow the guide at [another repository](https://github.com/loeeeee/loe-handbook-of-gpu-in-lxc/blob/main/src/gpu-passthrough.md) of mine.

After finishing all of the steps in that guide, the guest OS should execute command `nvidia-smi` without any error.

For immich machine learning support, we also need to install CuDNN,

```bash
apt install nvidia-cudnn
```

Zu easy, innit?

## Install utilities and databases

```bash
apt install curl git python3-venv python3-dev gcc
```

### Postgresql

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
\q
```

Note: change password.

### FFmpeg

To install ffmpeg, it is recommend not to use the ffmpeg in the Ubuntu APT repo, because hardware acceleration is not enabled at the compile time of that version of FFmpeg, which should not matter for CPU-only user. Instead, a version from [Jellyfin](https://jellyfin.org) that supports hardware acceleration is recommended, because that version is well-maintained and receive active updates. Here is how this could be done. The following commands is mostly copy-and-paste from [the official installation documentation](https://jellyfin.org/docs/general/installation/linux#repository-manual).

First, we need to add the repository of Jellyfin to the system package manager.

```bash
apt install curl gnupg software-properties-common
add-apt-repository universe
mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/jellyfin.gpg
export VERSION_OS="$( awk -F'=' '/^ID=/{ print $NF }' /etc/os-release )"
export VERSION_CODENAME="$( awk -F'=' '/^VERSION_CODENAME=/{ print $NF }' /etc/os-release )"
export DPKG_ARCHITECTURE="$( dpkg --print-architecture )"
cat <<EOF | sudo tee /etc/apt/sources.list.d/jellyfin.sources
Types: deb
URIs: https://repo.jellyfin.org/${VERSION_OS}
Suites: ${VERSION_CODENAME}
Components: main
Architectures: ${DPKG_ARCHITECTURE}
Signed-By: /etc/apt/keyrings/jellyfin.gpg
EOF
apt update
```

Then, we install the ffmpeg from Jellyfin.

```bash
apt install jellyfin-ffmpeg6
```

Finally, we soft link the Jellyfin ffmpeg to `/bin/`

```bash
ln -s /usr/lib/jellyfin-ffmpeg/ffmpeg  /bin/ffmpeg
ln -s /usr/lib/jellyfin-ffmpeg/ffprobe  /bin/ffprobe
```

Now, calling `ffmpeg` should output a long gibberish.

#### Alternative way of installing FFmpeg (Static build)

Download one from [FFmpeg Static Builds](https://johnvansickle.com/ffmpeg/).

```bash
wget https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz
tar -xf ffmpeg-git-amd64-static.tar.xz
cp ffmpeg-git-amd64-static/ffmpeg /bin/ffmpeg
```

### Redis

Immich works fine with the Redis in Ubuntu 22.04 APT repo. No additional config is needed.

```bash
apt install redis
```

Now, we are mostly ready to install the Immich server.

## Install Immich Server

Create a immich user, if you already done so in the above optional section, you may safely skip the following code block.

```bash
useradd -m immich
chsh immich # Optional: Change the default shell the immich user is using. Typically to /bin/bash
```

After creating the user, we should first install node.js for the user, immich.

### Node.js

Immich works on Node.js 20 LTS, and Ubuntu ships an ancient node.js. We need to go to [Node.js's download site](https://nodejs.org/en/download/package-manager) for a modern version.

Because npm/nvm by default use user installation, i.e, install the binary at the home directory of current user, the following code should be executed in the shell environment of whichever user that runs immich. Other installations in this tutorial are global, however, meaning that they should be executed in sudo/root privilege.

Assume one is currently login as user root, to change to the user we just created,

```bash
su immich
```

To change back to the pre-su user, `exit` should do the trick.

After change to the immich user, 

(The following script is copy-pasted from the node.js's download website.)

```bash
# installs NVM (Node Version Manager)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash

# Logout and login to reload the terminal so that nvm is available
# download and install Node.js
nvm install 20

# verifies the right Node.js version is in the environment
node -v # should print `v20.13.1`

# verifies the right NPM version is in the environment
npm -v # should print `10.5.2`
```

Note: We may set `NVM_NODEJS_ORG_MIRROR` [environment variables](https://github.com/nvm-sh/nvm/issues/2378) in bash to use a proxy for installing node js

