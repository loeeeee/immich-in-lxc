# Immich with CUDA/ROCm Support in LXC (w/o Docker)

[![Build immich on new release](https://github.com/tautomer/immich-in-lxc/actions/workflows/auto_build_immich.yml/badge.svg)](https://github.com/tautomer/immich-in-lxc/actions/workflows/auto_build_immich.yml)

A complete guide for installing Immich in LXC, VM, or bare-metal without Docker, but with 

- **CUDA/ROCm support for machine-learning** (if one choose so), 
- **hardware acceleration for transcoding**,
- **HEIF, RAW, and JXL support**,
- Experimental Intel iGPU/dGPU/NPU support for machine-learning (if one choose so), 
- easy and fast upgrade, and
- accessible proxy settings for PyPi and NPM registry.

## Introduction

[Immich](https://github.com/immich-app/immich) is a

> High performance self-hosted photo and video management solution

I really like Immich and its coherent experience across both mobile and web. However, the official Documents only provides Docker installation guide, which is less than ideal for a LXC user. But, in fairness to Immich, not providing a bare-metal installation guide can be justified, as it is more than a simple binary and does require some efforts to set up in current state.

**This guide is heavily inspired by another guide [Immich Native](https://github.com/arter97/immich-native), and the install script & service files are modified from the ones in that repo. KUDO to its author, arter97!** 

Compared to Immich Native, this repo additionally offers the support for CUDA-accelerated machine learning and (out-of-box) support for processing HEIF, i.e. common smart phone image format, and RAW, i.e. common fancy big camera image format, images.

### Why hardware acceleration?

> I paid for the whole Speedometer, I'm gonna use the whole Speedometer.
>
> -- Abraham Lincoln

Jokes aside, hardware acceleration really helps during importing library containing many videos, or live photos (essentially a photo and video bundle), or when one would like to switch to or test out a bigger and better machine learning model to improve smart search or face search functionality, which requires a redo of the entire indexing process. However, during current stage and foreseeable future, the heavy work of generating thumbnails will remain on using SIMD commands on CPU, and cannot be accelerated by GPU.

Lastly, by using this repo, one could reliably set up a hardware-accelerated Immich instance without much hassle. So why not.

## Immich Components


<details>
<summary>Not so important</summary>

- Immich
    - Web Server
    - Machine Learning Server
- Database
    - Redis
    - Postgresql
        - VectorChord
- System
    - Jellyfin-ffmpeg
    - Node.js
    - git
- (Optional) Reverse Proxy
    - Nginx
- (Optional) NVIDIA
    - Driver (i.e. CUDA Runtime)
    - CuDNN (Version 9)
- (Optional) AMD
    - ROCm driver (6.4.1)

As one could tell, it is a lot of works, and a lot of things to get right. However, Immich is quite resilience and will fall-back to a baseline default when hardware acceleration does not work.

For the simplicity of the guide, all the components are installed in a single LXC container. However, it is always possible to run different components in different LXC containers. As it is always a design choice.

<br>
</details>

## Host setup

<details>
<summary>Not so important</summary>

I am using `Proxmox VE 8` as the LXC host, which is based on `Debian 12`, and I have a NVIDIA GPU, with a proprietary driver (550) installed. Some others are using a N100 mini PC box with Intel Quick Sync. And all of these do not matter.

However, if possible, use an LXC or VM with `Ubuntu 24.04 LTS` as it offers an easier set-up.

<br>
</details>

## Prepare the LXC container, or whatever

First, create a LXC/VM normally. Make sure there is reasonable amount CPU and memory, because we are going to install and compile a lot of things, and it would not hurt to give it a bit more. For a CPU-only Immich server, there should be at least 8 GiB of storage, and one with nVidia GPU, at least 16 GiB storage needs to be available. However, once one starts using Immich, it will create a lot of cache (for thumbnails and low-res transcoded videos), so don't forget to resize the LXC volumes accordingly. 

Also, there is no need for a privileged container (which is not recommended in almost all scenarios), if one does not plan to mount a file system, e.g., NFS, SMB, etc., directly inside the LXC container.

This tutorial is tested on `Ubuntu 24.04 LTS` and `Debian 12` LXCs. Things will differ slightly in different distributions, though. Additionally, if one wants to have HW-accelerated ML, it is not recommend to use older release of `Ubuntu`, as it has older version of dependency in its repository, introducing additional complexity, like package pinning.

## Hardware-accelerated machine learning

<details>
<summary>Nvidia</summary>

Firstly, prepare a LXC with GPU available by following the guide at [another repository](https://github.com/loeeeee/loe-handbook-of-gpu-in-lxc/blob/main/src/gpu-passthrough.md) of mine. This process is referred to as NVIDIA GPU pass-through in LXC.

After finishing all of the steps in that guide, the guest OS should execute command `nvidia-smi` without any error.

The major component that Immch requires is [ONNX runtime](https://onnxruntime.ai/docs/execution-providers/CUDA-ExecutionProvider.html#requirementsto), and here we are installing its dependency.

<details>
<summary>Ubuntu 24.04</summary>

For Immich machine learning support in `Ubuntu`, we need to install CuDNN and CUDA Toolkit. The default cuDNN version in apt is version 8, which is no longer supported by ONNX Runtime. Thus, we need to install the latest version 9.

The CuDNN install commands are from [official website of NVIDIA](https://developer.nvidia.com/cudnn-downloads), and should all be run as root. Also, one should check the NVIDIA website for updates.

```bash
wget https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/cuda-keyring_1.1-1_all.deb
dpkg -i cuda-keyring_1.1-1_all.deb
apt-get update

apt-get -y install cudnn-cuda-12
```

In addition to the cuDNN, we also need libcublas12 things.

```bash
apt install -y libcublaslt12 libcublas12 libcurand10
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

<br>
</details>


<details>
<summary>Intel/OpenVINO</summary>

This part is intended for users who would like to utilize Intel's OpenVINO execution provider. ([System requirement](https://docs.openvino.ai/2024/about-openvino/release-notes-openvino/system-requirements.html), [List of supported devices](https://docs.openvino.ai/2024/about-openvino/compatibility-and-support/supported-devices.html)) The document listed the support for not only Intel iGPU and dGPU, but also its NPU, which seems very cool.

Disclaimer: This part is not yet tested by the repo owner, and it is composed based on documentation. However, success have been reported ([Issue #58](https://github.com/loeeeee/immich-in-lxc/issues/58)), even though one could not see the background tasks ([Issue #62](https://github.com/loeeeee/immich-in-lxc/issues/62)). 

<details>
<summary>Moe</summary>
Firstly, prepare a LXC with proper hardware available. For iGPU user, one could use `intel_gpu_top` to see its availability.

Then, install the dependency specified by Immich for Intel.

```bash
./dep-intel.sh
```

Finally, after first-time execution of the `install.sh`, which happens at later part of the guide (so safe to skip for now), modify the generated `.env` file.

```env
isCUDA=openvino
```

I know, this is ugly as hell, but whatever, it works.

Now, when installing Immich, it will be using OpenVINO as its ML backend.

<br>
</details>

<br>
</details>


<details>
<summary>Others</summary>

Since Immich depends on ONNX runtime, it is **possible** that other hardware that is not officially supported by Immich can be used to do machine learning tasks. The idea here is that installing the dependency for the hardware following [ONNX's instruction](https://onnxruntime.ai/docs/execution-providers/#summary-of-supported-execution-providers). 

Some users have also reported successful results using GPU Transcoding in Immich by following the Proxmox configurations from this video: [iGPU Transcoding In Proxmox with Jellyfin Media Center](https://www.youtube.com/watch?v=XAa_qpNmzZs) - Just avoid all the Jellyfin stuff and do the configurations on the Immich container instead. At the end, you should be able to use your iGPU Transcoding in Immich by going to needs to go to `Administration > Settings > Video Transcoding Settings > Hardware Acceleration > Acceleration API` and select `Quick Sync` to explicitly use the GPU to do the transcoding.

Good luck and have fun!

<br>
</details>


## Immich Installation

### User creation

First of all, create a Immich user, if you already done so in the above optional section, you may safely skip the following code block. The user created here will run Immich server.

```bash
adduser --shell /bin/bash --disabled-password immich --comment "Immich Mich"
# --shell changes the default shell the immich user is using. In this case it will use /bin/bash, instead of the default /bin/sh, which lacks many eye-candy
# --disabled-password skips creating password, and (sort of) only allows using su to access the user. If you need to change the password of the user, use the command: passwd immich
# --comment adds user contact info, not super useful but mandatory, probably thanks to Unix legacy.
apt install -y git
usermod -aG video,render immich
```

### Clone the repo

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

### Install custom photo-processing library

Likely because of license issue, many libraries included by distribution package managers do not support all the image format we want, e.g., HEIF, RAW, etc. Thus, we need compile these libraries from source. It can be painful to figure out how to do this, but luckily, I have already sorted out for you.

#### Install compile tools and compile 始める


Now `exit` the immich user, as the upcoming commands should be run as `root` user.

```bash
./pre-install.sh
```

It is just so satisfying to see the compiling log rolling down the terminal, ain't it? Look carefully at the log, though. There should not be any error. However, some warning about relink will pop up, which is normal.

### Config PostgreSQL like a champ


The following steps apply to both `Debian 12` and `Ubuntu 24.04` instances.

Enter PostgreSQL control interface

```bash
# As root
su postgres
# Now you are user:postgres
psql
```

In the psql interface, run:
```SQL
CREATE DATABASE immich;
CREATE USER immich WITH ENCRYPTED PASSWORD 'A_SEHR_SAFE_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE immich to immich;
ALTER USER immich WITH SUPERUSER;
\q
```

Note: change password, seriously.

Note: To change back to the pre-su user, `exit` should do the trick.

#### Database Migration for Existing Users (v1.133.0+)

**Note:** Starting with Immich v1.133.0, the project has migrated from pgvecto.rs to [VectorChord](https://github.com/tensorchord/VectorChord) for better performance and stability.

If you're upgrading from a version prior to v1.133.0 and have an existing Immich installation, you may need to perform a database migration. The migration from pgvecto.rs to VectorChord is automatic, but you should:

1. **Backup your database** before upgrading
2. Ensure you're upgrading from at least v1.107.2 or later

**Note:** If you have an existing `$INSTALL_DIR/runtime.env` (e.g. /home/immich/runtime.env) file with `DB_VECTOR_EXTENSION=pgvector`, you should update it to `DB_VECTOR_EXTENSION=vectorchord` for the new VectorChord extension.

For more details on the VectorChord migration, see the [official Immich v1.133.0 release notes](https://github.com/immich-app/immich/releases/tag/v1.133.0).

### Install Immich Server

The star of the show is the install script, i.e. `install.sh` in this repo. It installs or updates the current Immich instance. The Immich instance itself is stateless, thanks to its design. Thus, it is safe to delete the `app` folder that will resides inside `INSTALL_DIR` folder that we are about to config. 

Note: **DO NOT DELETE UPLOAD FOLDER SPECIFIED BY `INSTALL_DIR` IN `.env`**. It stores all the user-uploaded content. 

Also note: One should always do a snapshot of the media folder during the updating or installation process, just in case something goes horribly wrong.

#### The environment variables

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
- `isCUDA` when set to true, will install Immich with CUDA supprt. For other GPU Transcodings, this is likely to remain false. (available flag: true, false, openvino, rocm)
- For user with compromised network accessibility:
    - `PROXY_NPM` sets the mirror URL that npm will use, if empty, it will use the official one,
    - :new:`PROXY_NPM_DIST` sets the dist URL that node-gyp will use, if empty, it will use the official one, and
    - `PROXY_POETRY` sets the mirror URL that poetry will use, if empty, it will use the official one.

Note: The `immich` user should have read and write access to both `INSTALL_DIR` and `UPLOAD_DIR`.

Note: :new: means user might need to create the empty entry to make script run.

#### Run the script

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

Lastly, we need to review and modify the `runtime.env` that is inside your specified `INSTALL_DIR` (not the runtime.env inside this repo). The default values could also work, unless you changed the `DB_PASSWORD` when installing Postgres. 

**Note:** If your `DB_PASSWORD` contains special characters (such as `$`, `!`, etc.), you must wrap the value in single quotes, e.g., `DB_PASSWORD='your$pec!alP@ss'`. This prevents shell expansion issues when the environment file is sourced. (See [issue #95](https://github.com/loeeeee/immich-in-lxc/issues/95) for details.)

For Timezones `TZ`, you can consult them in the [TZ Database Wiki](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones#List).

#### Post install script

The post install script will copy the systemd service files to proper location (and overwrite the original ones), assuming one is using Ubuntu, or something similar. Additionally, it creates a folder for log at `/var/log/`. Both operation requires `sudo/root` privilege, so make sure to review the script before proceeding.

```bash
./post-install.sh
```

Then, modify the `service` files to make sure every path name is spelled correctly. You might need to modify the variables `WorkingDirectory`, `EnvironmentFile`, `ExecStart` with the `INSTALL_DIR` specified in the `.env` file (in case you didn't leave the default INSTALL_DIR).

```bash
nano /etc/systemd/system/immich-ml.service # Modify WorkingDirectory, EnvironmentFile, and ExecStart with your INSTALL_DIR, in case you changed it.
```
```bash
nano /etc/systemd/system/immich-web.service # Modify ExecStart with your INSTALL_DIR, in case you changed it.
```

After that, we are ready to start our Immich instance!

```bash
systemctl daemon-reload && \
systemctl start immich-ml && \
systemctl start immich-web
```

The default setting exposes the Immich web server on port `2283` on all available address. For security reason, one should put a reverse proxy, e.g. Nginx, HAProxy, in front of the immich instance and add SSL to it.

To make the service persistent and start after reboot,

```bash
systemctl enable immich-ml && \
systemctl enable immich-web
```

#### Immich config

Because we are install Immich instance in a none docker environment, some DNS lookup will not work. For instance, we need to change the URL inside `Administration > Settings > Machine Learning Settings > URL` to `http://localhost:3003`, otherwise the web server cannot communicate with the ML backend.

Additionally, for LXC with CUDA or other GPU Transcoding support enabled, one needs to go to `Administration > Settings > Video Transcoding Settings > Hardware Acceleration > Acceleration API` and select your GPU Transcoding (e.g., `NVENC` - for CUDA) to explicitly use the GPU to do the transcoding.

## Update the Immich instance

The Immich server instance is designed to be stateless, meaning that deleting the instance, i.e. the `INSTALL_DIR/app` folder, (NOT DATABASE OR OTHER STATEFUL THINGS) will not break anything. Thus, to upgrade the current Immich instance, all one needs to do is essentially install the latest Immich.

- **v1.133.0+ Breaking Changes:** If upgrading to v1.133.0 or later, ensure you're upgrading from at least v1.107.2 or later. If you're on an older version, upgrade to v1.107.2 first and ensure Immich starts successfully before continuing.

First thing to do is to stop the old instance.

```bash
systemctl stop immich-ml && \
systemctl stop immich-web
```

After stopping the old instance, update this repo by doing a `git pull` in the folder `immich-in-lxc` (using the `immich` user). 

Then, the modify `REPO_TAG` value in `.env` file based on the one in `install.env`. 

Finally, run the `install.sh` and it will update Immich, hopefully without problems.

Also, don't forget to start the service again, to load the latest Immich instance.
