# Immich with CUDA Support without Docker

Install Immich in LXC or bare-metal without Docker, but with optional CUDA support for machine-learning, (almost) universal hardware acceleration for transcoding and HEIF, RAW support.

## Introduction

[Immich](https://github.com/immich-app/immich) is a

> High performance self-hosted photo and video management solution

I really like Immich and its coherent experience in both mobile and web. However, the official Documents only provides Docker installation guide, which is less than ideal for a LXC user.

But, not providing a bare-metal installation guide for Immich can be justified as Immich is more than a simple binary and does require some efforts to set up in current state.

**This guide is heavily inspired by another guide [Immich Native](https://github.com/arter97/immich-native), and the install script & service files are modified from the ones in that repo. KUDO to its author, arter97!** 

Compared to Immich Native, this repo additionally offers the support for CUDA-accelerated machine learning and (out-of-box) support for processing HEIF, i.e. common smart phone image format, and RAW, i.e. common fancy big camera image format, images.

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

I am using `Proxmox VE 8` as the LXC host, which is based on `Debian`, and I have a NVIDIA GPU, with a proprietary driver (550) installed. Some others are using a N100 mini PC box with Intel Quick Sync. And all of these do not matter.

However, if possible, use an LXC with `Ubuntu 24.04 LTS` as it offers an easier set-up.

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

<details>
<summary>Ubuntu 24.04</summary>

For Immich machine learning support, we also need to install CuDNN and two additional libraries,

```bash
apt install nvidia-cudnn libcublaslt12 libcublas12
```

<br>
</details>

<details>
<summary>Debian 12</summary>

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

<br>
</details>

Zu easy, innit?

## Hardware-accelerated machine learning: Others (Optional)

Since Immich depends on ONNX runtime, it is **possible** that other hardware that is not officially supported by Immich can be used to do machine learning tasks. The idea here is that installing the dependency for the hardware following [ONNX's instruction](https://onnxruntime.ai/docs/execution-providers/). 

Some users have also reported successful results using GPU Transcoding in Immich by following the Proxmox configurations from this video: [iGPU Transcoding In Proxmox with Jellyfin Media Center](https://www.youtube.com/watch?v=XAa_qpNmzZs) - Just avoid all the Jellyfin stuff and do the configurations on the Immich container instead. At the end, you should be able to use your iGPU Transcoding in Immich by going to needs to go to `Administration > Settings > Video Transcoding Settings > Hardware Acceleration > Acceleration API` and select `Quick Sync` to explicitly use the GPU to do the transcoding.

Good luck and have fun!

## Install utilities and databases

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

### FFmpeg with Hardware-acceleration

Not all FFmpeg are built equal. In most cases, the ffmpeg shipped from distribution package manager does not support any kind of hardware acceleration. However, there is an easy fix, thanks to the great contributions made by Jellyfin team, as they maintain a version of FFmpeg that receives timely update and support most common hardware for more efficient transcoding. The list of supported hardware can be found at [*Supported Acceleration Methods*](https://jellyfin.org/docs/general/administration/hardware-acceleration#supported-acceleration-methods), and the list includes common hardware features, like NVENC, and QSV, or universal interface, like VAAPI. Here, we will be using this FFmpeg build to enable hw-acceleration in our Immich server.

Side note, after some digging around, I found out that the official Immich docker image uses FFmpeg from Jellyfin as well. What a coincidence.

To install the FFmpeg made by Jellyfin team, first, we need to add the repository of Jellyfin to the system package manager. Jellyfin documentation suggests slightly different approaches for `Ubuntu` and `Debian` for adding the repository.

<details>
<summary>Ubuntu 24.04</summary>

The following commands is mostly copy-and-paste from [the official installation documentation](https://jellyfin.org/docs/general/installation/linux#repository-manual), and is for `Ubuntu` and its derivatives. This terrifying chunk of commands add the Jellyfin repository to package manager.

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
```

<br>
</details>

<details>
<summary>Debian 12</summary>

Jellyfin documentation suggests a super simple way of adding Jellyfin repository, and only for `Debian`, and NO, `Ubuntu` is not supported. `Debian` for the win!

```bash
apt install extrepo
extrepo enable jellyfin
```

<br>
</details>

After one has added the Jellyfin repo into their package manager's list, we can install the FFmpeg from Jellyfin.

```bash
apt update
apt install jellyfin-ffmpeg6
```

Finally, we soft link the Jellyfin FFmpeg to `/usr/bin/`

We do not want to link the binary to `/bin` because in `Debian` and its derivatives, which includes `Ubuntu`, because the entire `/bin` folder is softlinked to `/usr/bin`. but doing either way does not seem to have a practical difference, besides linking to `/usr/bin` makes my brain happier.

```bash
ln -s /usr/lib/jellyfin-ffmpeg/ffmpeg  /usr/bin/ffmpeg
ln -s /usr/lib/jellyfin-ffmpeg/ffprobe  /usr/bin/ffprobe
```

Now, calling `ffmpeg` should output a long gibberish, at least for normies.

<details>
<summary><h4>Alternative way of installing the latest FFmpeg (static build)</h4></summary>

Download one from [FFmpeg Static Builds](https://johnvansickle.com/ffmpeg/). This may be the preferred way for a CPU-only user -- less complexity, less headache.

```bash
wget https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz
tar -xf ffmpeg-git-amd64-static.tar.xz
cp ffmpeg-git-amd64-static/ffmpeg /bin/ffmpeg
```

<br>
</details>

<details>
<summary><h4>Alternative way of installing a FFmpeg (system package manager)</h4></summary>

Download one from one's system package manager. Super simple.

```bash
apt install ffmpeg
```

<br>
</details>

### Redis

Immich works fine with the Redis in Ubuntu 24.04 repo. No additional config is needed.

```bash
apt install redis
```

### Git

Git will be needed later. It works fine with Ubuntu 24.04 repo, so no additional config is needed.

```bash
apt install git
```

### Immich User Creation

First of all, create a Immich user, if you already done so in the above optional section, you may safely skip the following code block. The user created here will run Immich server.

```bash
useradd -m immich
chsh -s /bin/bash immich # This optional setting changes the default shell the immich user is using. In this case it will use /bin/bash, instead of the default /bin/sh, which lacks many eye-candy
# If you need to change the password of the user, use the command: passwd immich
# If the user immich needs sudo permissions, which is very very unlikely, use the command as root user: usermod -aG sudo immich
```

After creating the user, we should first install node.js for the user, Immich.

### Node.js

Immich works on a recent Node.js 20 LTS, and Ubuntu ships an ancient node.js. Thus. we need to go to [Node.js's download site](https://nodejs.org/en/download/package-manager) for the modern version.

Because npm/nvm by default uses user installation, i.e, installing the binary at the home directory of current user, the following code should be executed in the shell environment of whichever user that runs Immich. Other installations, besides the coming installation script (`install.sh`), in this tutorial are global, however, meaning that they should be executed in sudo/root privilege.

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
node -v # should print `v20.*.*`
# verifies the right npm version is in the environment
npm -v # should print `10.*.*`
```

Now `exit` the immich user.

Note: We may set `NVM_NODEJS_ORG_MIRROR` [environment variables](https://github.com/nvm-sh/nvm/issues/2378) in bash to use a proxy for installing node js

## Install custom photo-processing library

Likely because of license issue, many libraries included by distribution package managers do not support all the image format we want, e.g., HEIF, RAW, etc. Thus, we need compile these libraries from source. It can be painful to figure out how to do this, but luckily, I have already sorted out for you.

Firstly, change the locale, not sure why, only because Perl requires so.

### Locale

Open `/etc/locale.gen`, find line,

> \# en_US.UTF-8 UTF-8

Uncomment the line, save the file, and run the following command as `sudo/root` user:

```bash
locale-gen
```

### Install compile tools

I have make some helper script in this repo, so all one needs to do is clone the repo. We change to the user immich so that the files we cloned will have proper permission. And, just in case one does not know, the commands are as follow.

```bash
su immich
cd ~
git clone https://github.com/loeeeee/immich-in-lxc.git
```

Additionally, it is recommend to have our working directory set to the repo's directory.

```bash
cd immich-in-lxc
```

Now `exit` the immich user, as the upcoming commands should be run as `sudo/root` user.

<details>
<summary>Debian 12</summary>

Unlucky you! Debian 12's package manager does not include all the essentials we need. Thus, we need to use packages from the future, i.e. packages that are marked as testing.

To do so, head to `/etc/apt/source.list`.

At the end of the file, add,

```bash
deb http://deb.debian.org/debian testing main contrib
```

Now, Debian will have the knowledge of packages under testing.

Next, to make sure the testing packages do not overwrite the good stable packages, we need to specify our install preference.

```bash
cat > /etc/apt/preferences.d/preferences << EOL
Package: *
Pin: release a=testing
Pin-Priority: 450
EOL
```

Finally, in the repo folder, execute

```bash
./dep-debian.sh
```

It will install all the dependency for coming steps.

<br>
</details>

<details>
<summary>Ubuntu 24.04</summary>

Lucky boiiiii! Ubuntu package manager has everything we need. 

All we need to do is to run the following command as `sudo/root` user (not immich user):

```bash
cd /home/immich/immich-in-lxc/
./dep-ubuntu.sh
```

This will install all the dependencies for the upcoming steps.

<br>
</details>

### Compile 始める

After installing the essential bundle, run the following command as `sudo/root` user (not immich user):

```bash
./pre-install.sh
```

Look carefully at the log, though. There should not be any error. However, some warning about relink will pop up, which is normal.

## Install Immich Server

The star of the show is the install script, i.e. `install.sh` in this repo. It installs or updates the current Immich instance. The Immich instance itself is stateless, thanks to its design. Thus, it is safe to delete the `app` folder that will resides inside `INSTALL_DIR` folder that we are about to config. 

Note: **DO NOT DELETE UPLOAD FOLDER SPECIFIED BY `INSTALL_DIR` IN `.env`**. It stores all the user-uploaded content. 

Also note: One should always do a snapshot of the media folder during the updating or installation process, just in case something goes horribly wrong.

### The environment variables

An example .env file that will be generated when no `.env` file is found inside current working directory when executing the script.

Let us go ahead and execute the script as `immich` user (or the user that will be running immich). No worry, when `.env` file is not found, the script will gracefully exit and will not change to the file system.

```bash
su immich # Or the user who is going to run immich. It should be the same user as the one used for installing Node.js.
./install.sh
```

Then, we should have a `.env` file in current directory. 

- `REPO_TAG` is the version of the Immich that we are going to install,
- `INSTALL_DIR` is where the `app` and `source` folders will resides in (e.g., it can be a `mnt` point),
- `UPLOAD_DIR` is where the user uploads goes to  (it can be a `mnt` point), 
- `isCUDA` when set to true, will install Immich with CUDA supprt. For other GPU Transcodings, this is likely to remain false.
- `PROXY_NPM` sets the mirror URL that npm will use, if empty, it will use the official one, and
- `PROXY_POETRY` sets the mirror URL that poetry will use, if empty, it will use the official one.

Note: The `immich` user should have read and write access to both `INSTALL_DIR` and `UPLOAD_DIR`.

### Run the script

After the `.env` is properly configured, we are now ready to do the actual installation.

```bash
./install.sh
```

Note, `install.sh` should be executed as user `immich`, or the user who is going to run immich.

It should go without errors, just like ever dev says.

After several minutes, ideally, it would say,

```bash
Done. Please install the systemd services to start using Immich.
```

Lastly, we need to review and modify the `runtime.env` that is inside your specified `INSTALL_DIR` (not the runtime.env inside this repo). The default values could also work, unless you changed the `DB_PASSWORD` when installing Postgres. For Timezones `TZ`, you can consult them in the [TZ Database Wiki](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones#List).

### Post install script

The post install script will copy the systemd service files to proper location (and overwrite the original ones), assuming one is using Ubuntu, or something similar. Additionally, it creates a folder for log at `/var/log/`. Both operation requires `sudo/root` privilege, so make sure to review the script before proceeding.

```bash
./post-install.sh
```

Then, modify the `service` files to make sure every path name is spelled correctly. You might need to modify the variables `WorkingDirectory`, `EnvironmentFile`, `ExecStart` with the `INSTALL_DIR` specified in the `.env` file (in case you didn't leave the default INSTALL_DIR).

```bash
nano /etc/systemd/system/immich-ml.service # Modify WorkingDirectory, EnvironmentFile, and ExecStart with your INSTALL_DIR, in case you changed it.
```
```bash
nano /etc/systemd/system/immich-microservices.service # Modify ExecStart with your INSTALL_DIR, in case you changed it.
```
```bash
nano /etc/systemd/system/immich-web.service # Modify ExecStart with your INSTALL_DIR, in case you changed it.
```

After that, we are ready to start our Immich instance!

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

### Immich config

Because we are install Immich instance in a none docker environment, some DNS lookup will not work. For instance, we need to change the URL inside `Administration > Settings > Machine Learning Settings > URL` to `http://localhost:3003`, otherwise the web server cannot communicate with the ML backend.

Additionally, for LXC with CUDA or other GPU Transcoding support enabled, one needs to go to `Administration > Settings > Video Transcoding Settings > Hardware Acceleration > Acceleration API` and select your GPU Transcoding (e.g., `NVENC` - for CUDA) to explicitly use the GPU to do the transcoding.

## Update the Immich instance

The Immich server instance is designed to be stateless, meaning that deleting the instance, i.e. the `INSTALL_DIR/app` folder, (NOT DATABASE OR OTHER STATEFUL THINGS) will not break anything. Thus, to upgrade the current Immich instance, all one needs to do is essentially install the latest Immich.

Before the update, one should **backup or at least snapshot the current container**.

First thing to do is to stop the old instance.

```bash
systemctl stop immich-microservices && \
systemctl stop immich-ml && \
systemctl stop immich-web
```

After stopping the old instance, update this repo by doing a `git pull` in the folder `immich-in-lxc` (using the `immich` user). 

Then, the modify `REPO_TAG` value in `.env` file based on the one in `install.env`. 

Finally, run the `install.sh` and it will update Immich, hopefully without problems.

Also, don't forget to start the service again, to load the latest Immich instance.
