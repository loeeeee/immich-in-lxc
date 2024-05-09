#!/bin/bash

set -xeuo pipefail

REPO_TAG=v1.103.1

IMMICH_INSTALL_PATH=/var/lib/immich
IMMICH_INSTALL_PATH_APP=$IMMICH_INSTALL_PATH/app

if [[ "$USER" != "immich" ]]; then
  # Disable systemd services, if installed
  (
    for i in immich*.service; do
      systemctl stop $i && \
        systemctl disable $i && \
        rm /etc/systemd/system/$i &&
        systemctl daemon-reload
    done
  ) || true

  mkdir -p $IMMICH_INSTALL_PATH
  chown immich:immich $IMMICH_INSTALL_PATH

  mkdir -p /var/log/immich
  chown immich:immich /var/log/immich

  echo "Restarting the script as user immich"
  exec sudo -u immich $0 $*
fi

BASEDIR=$(dirname "$0")

rm -rf $IMMICH_INSTALL_PATH_APP
mkdir -p $IMMICH_INSTALL_PATH_APP

# Wipe npm, pypoetry, etc
# This expects immich user's home directory to be on $IMMICH_INSTALL_PATH/home
rm -rf $IMMICH_INSTALL_PATH/home
mkdir -p $IMMICH_INSTALL_PATH/home


# Clone repo
REPO_BASE=/tmp/immich
REPO_URL="https://github.com/immich-app/immich"

if [ ! -d "$REPO_BASE" ]; then
  git clone "$REPO_URL"
fi

cd $REPO_BASE
git reset --hard $REPO_TAG

# Install immich-server
cd server
npm ci
npm run build
npm prune --omit=dev --omit=optional
cd -

cd open-api/typescript-sdk
npm ci
npm run build
cd -

cd web
npm ci
npm run build
cd -

cp -a server/node_modules server/dist server/bin $IMMICH_INSTALL_PATH_APP/
cp -a web/build $IMMICH_INSTALL_PATH_APP/www
cp -a server/resources server/package.json server/package-lock.json $IMMICH_INSTALL_PATH_APP/
cp -a server/start*.sh $IMMICH_INSTALL_PATH_APP/
cp -a LICENSE $IMMICH_INSTALL_PATH_APP/
cd $IMMICH_INSTALL_PATH_APP
# npm cache clean --force
cd -

# immich-machine-learning
IMMICH_MACHINE_LEARNING_PATH=$IMMICH_INSTALL_PATH_APP/machine-learning
mkdir -p $IMMICH_MACHINE_LEARNING_PATH
python3 -m venv $IMMICH_MACHINE_LEARNING_PATH/venv
(
  # Initiate subshell to setup venv
  . $IMMICH_MACHINE_LEARNING_PATH/venv/bin/activate
  pip3 install poetry
  cd machine-learning
  export POETRY_PYPI_MIRROR_URL=https://mirror.sjtu.edu.cn/pypi/web/simple
  if false; then # Set this to true to force poetry update
    # Allow Python 3.12 (e.g., Ubuntu 24.04)
    sed -i -e 's/<3.12/<4/g' pyproject.toml
    poetry update
  fi
  poetry install --no-root --with dev --with cuda
  cd ..
)
cp -a machine-learning/ann machine-learning/start.sh machine-learning/app $IMMICH_MACHINE_LEARNING_PATH/

# Replace /usr/src
cd $IMMICH_INSTALL_PATH_APP
grep -Rl /usr/src | xargs -n1 sed -i -e "s@/usr/src@$IMMICH_INSTALL_PATH@g"
ln -sf $IMMICH_INSTALL_PATH/app/resources $IMMICH_INSTALL_PATH/
mkdir -p $IMMICH_INSTALL_PATH/cache
sed -i -e "s@\"/cache\"@\"$IMMICH_INSTALL_PATH/cache\"@g" $IMMICH_MACHINE_LEARNING_PATH/app/config.py

# Install sharp
cd $IMMICH_INSTALL_PATH_APP
npm install sharp

# Setup upload directory
mkdir -p $IMMICH_INSTALL_PATH/upload
ln -s $IMMICH_INSTALL_PATH/upload $IMMICH_INSTALL_PATH_APP/
ln -s $IMMICH_INSTALL_PATH/upload $IMMICH_MACHINE_LEARNING_PATH/

# Use 127.0.0.1
# sed -i -e "s@app.listen(port)@app.listen(port, '127.0.0.1')@g" $IMMICH_INSTALL_PATH_APP/dist/main.js

# Custom start.sh script
cat <<EOF > $IMMICH_INSTALL_PATH_APP/start.sh
#!/bin/bash

set -a
. $IMMICH_INSTALL_PATH/env
set +a

cd $IMMICH_INSTALL_PATH_APP
exec node $IMMICH_INSTALL_PATH_APP/dist/main "\$@"
EOF

cat <<EOF > $IMMICH_MACHINE_LEARNING_PATH/start.sh
#!/bin/bash

set -a
. $IMMICH_INSTALL_PATH/env
set +a

cd $IMMICH_MACHINE_LEARNING_PATH
. venv/bin/activate

: "\${MACHINE_LEARNING_HOST:=127.0.0.1}"
: "\${MACHINE_LEARNING_PORT:=3003}"
: "\${MACHINE_LEARNING_WORKERS:=1}"
: "\${MACHINE_LEARNING_WORKER_TIMEOUT:=120}"

exec gunicorn app.main:app \
        -k app.config.CustomUvicornWorker \
        -w "\$MACHINE_LEARNING_WORKERS" \
        -b "\$MACHINE_LEARNING_HOST":"\$MACHINE_LEARNING_PORT" \
        -t "\$MACHINE_LEARNING_WORKER_TIMEOUT" \
        --log-config-json log_conf.json \
        --graceful-timeout 0
EOF

# Cleanup
# rm -rf $REPO_BASE

echo
echo "Done. Please install the systemd services to start using Immich."
echo