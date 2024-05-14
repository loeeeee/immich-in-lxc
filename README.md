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

Follow the guide at [another repository](https://github.com/loeeeee/lxc-gpu-passthrough) of mine.

After finishing all of the steps in that guide, the guest OS should execute command `nvidia-smi` without any error.

For immich machine learning support, we also need to install CuDNN,

```bash
apt install nvidia-cudnn
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

To install ffmpeg, it is recommend not to use the ffmpeg in the Ubuntu APT repo, because hardware acceleration is not enabled at the compile time of that version of FFmpeg, which should not matter for CPU-only user. Instead, a version from [Jellyfin](https://jellyfin.org) is recommended, because that version is well-maintained and receive active updates. Here is how this could be done. The following commands is mostly copy-and-paste from [the official installation documentation](https://jellyfin.org/docs/general/installation/linux#repository-manual).

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
ln -s /usr/lib/jellyfin/jellyfin-ffmpeg  /bin/ffmpeg
ln -s /usr/lib/jellyfin/jellyfin-ffprobe  /bin/ffprobe
```

Now, calling `ffmpeg` should output a long gibberish.

##### Alternative way of installing FFmpeg (Static build)

Download one from [FFmpeg Static Builds](https://johnvansickle.com/ffmpeg/).

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
