# Immich in LXC with Optional CUDA support

Install Immich in LXC without using Docker, but with optional CUDA support. This guide should also be applicable to any bare-metal installation, even the ones with Intel or AMD GPUs.

## Introduction

[Immich](https://github.com/immich-app/immich) is a

> High performance self-hosted photo and video management solution

I really like Immich and its coherent experience in both mobile and web. However, the official Documents only provides Docker installation guide, which is less than ideal for a LXC user.

But, not providing a bare-metal installation guide for Immich can be justified as Immich is more than a simple binary and does require some efforts to set up in current state.

**This guide is heavily inspired by another guide [Immich Native](https://github.com/arter97/immich-native), and the install script & service files are modified from the ones in that repo. KUDO to its author, arter97!** 

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
    - CuDNN (Version 9)

As one could tell, it is a lot of works, and a lot of things to get right. However, Immich is quite resilience and will fall-back to a baseline default when hardware-acceleration does not work.

For the simplicity of the guide, all the components are installed in a single LXC container. However, it is always possible to run different components in different LXC containers. As it is always a design choice.

## Host setup

I am using `Proxmox VE 8` as the LXC host, which is based on `Debian`, and I have a NVIDIA GPU, with a proprietary driver (550) installed. 

## Prepare the LXC container

First, create a LXC normally. Make sure there is reasonable amount CPU and memory, because we are going to install and compile a lot of things, and it would not hurt to give it a bit more. For a CPU-only Immich server, there should be at least 8 GiB of storage, and a NVIDIA GPU one should have at least 16 GiB to have it installed. However, once one starts using Immich, it will create a lot of caching, so don't forget to resize the LXC volumes accordingly. 

Also, there is no need for a privileged container, if one does not plan to mount a file system directly inside the LXC container.

This tutorial is tested on `Ubuntu 24.04 LTS` and `Debian 12` LXCs. Things will differ in different distros, though. Additionally, if one wants to have HW-accelerated ML, it is not recommend to use older release of `Ubuntu`, as it has older version of dependency in its repository, introducing additional complexity.

## Mount host volume to LXC container (Optional)

This part of the guide is about mounting a directory from the host to a unprivileged container. The directory can be a SMB or a NFS share that is already mounted on the host, or any other local directory.

Follow the guide at [another repository](https://github.com/loeeeee/loe-handbook-of-gpu-in-lxc/blob/main/src/mount-host-volume.md) of mine.

And, that is it, EZ, right?

## Hardware-accelerated machine learning: NVIDIA (Optional)

Firstly, prepare a LXC with GPU available by following the guide at [another repository](https://github.com/loeeeee/loe-handbook-of-gpu-in-lxc/blob/main/src/gpu-passthrough.md) of mine. This process is referred to as NVIDIA GPU pass-through in LXC.

After finishing all of the steps in that guide, the guest OS should execute command `nvidia-smi` without any error.

The major component that Immch requires is [ONNX runtime](https://onnxruntime.ai/docs/execution-providers/CUDA-ExecutionProvider.html#requirementsto), and here we are installing its dependency.

### Ubuntu

For Immich machine learning support, we also need to install CuDNN and two additional libraries,

```bash
apt install nvidia-cudnn libcublaslt12 libcublas12
```

### Debian

For Immich machine learning support in `Debian`, we need to install CuDNN and CUDA Toolkit.

We install the entire CUDA Toolkit because install `libcublas` depends on CUDA Toolkit, and when install the toolkit, this right version of this component will be included.

The CuDNN install commands are from [official website of NVIDIA](https://developer.nvidia.com/cudnn-downloads), and should all be run as root. Also, one should check the NVIDIA website for updates.

```bash
# CuDNN part
wget https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
add-apt-repository contrib
apt-get update
apt-get -y install cudnn
## Specified by NVIDIA, but does not seem to install anything
apt-get -y install cudnn-cuda-12

# CUDA Toolkit part
apt install -y cuda-toolkit
```

Zu easy, innit?

## Hardware-accelerated machine learning: Others (Optional)

Since Immich depends on ONNX runtime, it is **possible** that other hardware that is not officially supported by Immich can be used to do machine learning tasks. The idea here is that installing the dependency for the hardware following [ONNX's instruction](https://onnxruntime.ai/docs/execution-providers/). Good luck and have fun!

## Install utilities and databases

```bash
apt install curl git python3-venv python3-dev build-essential unzip
```

## To build base-images of Immich

### Locale

Open `/etc/locale.gen`, find line,

> \# en_US.UTF-8 UTF-8

Uncomment the line, save the file, and

```bash
locale-gen
```

### Build essentials

Execute `dep-{distro}.sh` to install required packages.

After the installation, run

```bash
pre-install.sh
```

### Postgresql

As for postgresql, visit [official guide](https://www.postgresql.org/download/linux/ubuntu/) for latest guide on installing postgresql 16 and adding extension repo, as immich depends on a vector extension.

```bash
apt install -y postgresql-common
/usr/share/postgresql-common/pgdg/apt.postgresql.org.sh
apt -y install postgresql
apt install postgresql-16-pgvector
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

Note: To change back to the pre-su user, `exit` should do the trick.

### FFmpeg

For a CUDA user, to install ffmpeg, it is recommend not to use the ffmpeg in the Ubuntu APT repo, because its hardware acceleration is not enabled at the compile time. Instead, a version from [Jellyfin](https://jellyfin.org) that supports all kinds of hardware acceleration is recommended, because that version is well-maintained and receive active updates. And here is how this could be done.

First, we need to add the repository of Jellyfin to the system package manager. The following commands is mostly copy-and-paste from [the official installation documentation](https://jellyfin.org/docs/general/installation/linux#repository-manual), and is for `Ubuntu` and its derivative only. 

A `Debian` user should go to its official install documentation and follow the instruction there. Though, the difference is subtle. One should follow the instruction until just before installing the entire Jellyfin ---- we don't need that here, only its FFmpeg component.

```bash
apt install curl gnupg software-properties-common
add-apt-repository universe
mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.jellyfin.org/jellyfin_team.gpg.key | gpg --dearmor -o /etc/apt/keyrings/jellyfin.gpg
export VERSION_OS="$( awk -F'=' '/^ID=/{ print $NF }' /etc/os-release )"
export VERSION_CODENAME="$( awk -F'=' '/^VERSION_CODENAME=/{ print $NF }' /etc/os-release )"
export DPKG_ARCHITECTURE="$( dpkg --print-architecture )"
cat <<EOF | tee /etc/apt/sources.list.d/jellyfin.sources
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

Download one from [FFmpeg Static Builds](https://johnvansickle.com/ffmpeg/). This may be the preferred way for a CPU-only user -- less things, less headache.

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

Create a Immich user, if you already done so in the above optional section, you may safely skip the following code block.

```bash
useradd -m immich
chsh immich # Optional: Change the default shell the immich user is using. Typically to /bin/bash
```

After creating the user, we should first install node.js for the user, Immich.

### Node.js

Immich works on Node.js 20 LTS, and Ubuntu ships an ancient node.js. We need to go to [Node.js's download site](https://nodejs.org/en/download/package-manager) for a modern version.

Because npm/nvm by default use user installation, i.e, install the binary at the home directory of current user, the following code should be executed in the shell environment of whichever user that runs Immich. Other installations in this tutorial are global, however, meaning that they should be executed in sudo/root privilege.

Assume one is currently login as user root, to change to the user we just created,

```bash
su immich
```

To change back to the pre-su user, `exit` should do the trick.

After change to the Immich user, 

(The following script is copy-pasted from the node.js's download website.)

```bash
# installs nvm (Node Version Manager)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.0/install.sh | bash
# download and install Node.js (you may need to restart the terminal)
nvm install 20
# verifies the right Node.js version is in the environment
node -v # should print `v20.17.0`
# verifies the right npm version is in the environment
npm -v # should print `10.8.2`
```

Note: We may set `NVM_NODEJS_ORG_MIRROR` [environment variables](https://github.com/nvm-sh/nvm/issues/2378) in bash to use a proxy for installing node js

### The install script

The install script is the `install.sh` in this repo. It installs or update the current Immich instance. The Immich instance itself is stateless, thanks to its containerized nature. Thus, it is safe to delete the `app` folder that will resides inside `INSTALL_DIR` folder that we are about to config. **DO NOT DELETE UPLOAD FOLDER IN THE `INSTALL_DIR`**. It stores all the uploaded content. Also, one should always a snapshot of the media folder during the updating or installation process, just in case something goes horribly wrong.

#### Clone this repo

Just in case one does not know, 

```bash
git clone https://github.com/loeeeee/immich-in-lxc.git
```

#### Change directory

It is recommend to have our working directory set to the repo's directory.

```bash
cd immich-in-lxc
```

#### The environment variables

An example .env file that will be generated when no `.env` file is found inside current working directory when executing the script.

Let us go ahead and execute the script. No worry, when `.env` file is not found, the script will gracefully exit and do no change to the file system.

```bash
./install.sh
```

Then, we should have a `.env` file in current directory. 

- `REPO_TAG` is the version of the Immich that we are going to install,
- `INSTALL_DIR` is where the `app`, `source` folder will resides in,
- `UPLOAD_DIR` is where the user uploads goes to, 
- `isCUDA` when set to true, will install Immich with CUDA supprt, otherwise, only CPU will be used by Immich,
- `PROXY_NPM` sets the mirror URL that npm will use, if empty, it will use the official one, and
- `PROXY_POETRY` sets the mirror URL that poetry will use, if empty, it will use the official one.

Note: The `immich` user should have read and write access to both `INSTALL_DIR` and `UPLOAD_DIR`.

#### Run the script

After the `.env` is properly configured, we are now ready to do the actual installation.

```bash
./install.sh
```

It should go without errors, just like ever dev says.

After several minutes, ideally, it would say,

```bash
Done. Please install the systemd services to start using Immich.
```

Lastly, we need to review and modify the runtime.env that is inside `INSTALL_DIR` (not the one inside this repo). The default value should do the job, though.

#### Post install script

The post install script will copy the systemd service files to proper location (and overwrite the original ones), assuming one is using Ubuntu, or something similar. Additionally, it creates a folder for log at `/var/log/`. Both operation requires `sudo/root` privilege, so make sure to review the script before proceeding.

```bash
./post-install.sh
```

Then, modify the service file to make sure every path name is spelled correctly.

After that, we are now ready to start our Immich instance!

```bash
systemctl daemon-reload && \
systemctl start immich-microservices && \
systemctl start immich-ml && \
systemctl start immich-web
```

The default setting exposes the Immich web server on port `3001` on all available address. For security reason, one should put a reverse proxy, e.g. Nginx, HAProxy, in front of the immich instance and add SSL to it.

To make the service persistent and start after reboot,

```bash
systemctl enable immich-microservices && \
systemctl enable immich-ml && \
systemctl enable immich-web
```

#### Immich config

Because we are install Immich instance in a none docker environment, some DNS lookup will not work. For instance, we need to change the URL inside `Administration > Settings > Machine Learning Settings > URL` to `http://localhost:3003`, otherwise the web server cannot communicate with the ML backend.

Additionally, for LXC with CUDA support enabled, one needs to go to `Administration > Settings > Video Transcoding Settings > Hardware Acceleration > Acceleration API` and select NVENC to explicitly use the GPU to do the transcoding.

## Update the Immich instance

The Immich server instance is designed to be stateless, meaning that deleting the instance, i.e. the `INSTALL_DIR/app` folder, (NOT DATABASE OR OTHER STATEFUL THINGS) will not break anything. Thus, to upgrade the current Immich instance, all one needs to do is essentially install the latest Immich.

Before the update, one should **backup or at least snapshot the current container**.

First thing to do is to stop the old instance.

```bash
systemctl stop immich-microservices && \
systemctl stop immich-ml && \
systemctl stop immich-web
```

After that update this repo, i.e. do a `git pull` in folder `immich-in-lxc`. 

Then, the modify `REPO_TAG` value in `.env` file based on the one in `install.env`. 

Finally, run the `install.sh`, and it will update Immich, hopefully without problems.

Also, don't forget to start the service to load the latest Immich instance.
