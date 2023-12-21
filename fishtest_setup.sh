#!/bin/bash
# 231209
# to setup a fishtest server on Ubuntu 18.04 (bionic), 20.04 (focal) or 22.04 (jammy), simply run:
# sudo bash setup_fishtest.sh 2>&1 | tee setup_fishtest.sh.log
#
# to use fishtest connect a browser to:
# http://<ip_address> or http://<fully_qualified_domain_name>

user_name='fishtest'
user_pwd='Rijndael128192256!!'
# try to find the ip address
server_name=$(hostname --all-ip-addresses)
server_name="${server_name#"${server_name%%[![:space:]]*}"}"
server_name="${server_name%"${server_name##*[![:space:]]}"}"
# use a fully qualified domain names (http/https)
# server_name='<fully_qualified_domain_name>'

git_user_name='your_name'
git_user_email='you@example.com'

# create user for fishtest
useradd -m -s /bin/bash ${user_name}
echo ${user_name}:${user_pwd} | chpasswd
usermod -aG sudo ${user_name}
sudo -i -u ${user_name} << EOF
mkdir .ssh
chmod 700 .ssh
touch .ssh/authorized_keys
chmod 600 .ssh/authorized_keys
EOF

# get the user $HOME
user_home=$(sudo -i -u ${user_name} << 'EOF'
echo ${HOME}
EOF
)

# add some bash variables
sudo -i -u ${user_name} << 'EOF'
cat << 'EOF0' >> .profile

export FISHTEST_HOST=127.0.0.1
export AWS_ACCESS_KEY_ID=
export AWS_SECRET_ACCESS_KEY=
export VENV="$HOME/fishtest/server/env"
export NSVENV="$HOME/net-server/env"
EOF0
EOF

# set secrets
sudo -i -u ${user_name} << EOF
echo '' > fishtest.secret
echo '' > fishtest.captcha.secret
echo 'http://127.0.0.1/upload_net/' > fishtest.upload

cat << EOF0 > .netrc
# GitHub authentication to raise API rate limit
# create a <personal-access-token> https://github.com/settings/tokens
#machine api.github.com
#login <personal-access-token>
#password x-oauth-basic
EOF0
chmod 600 .netrc
EOF

# install required packages
apt update && apt full-upgrade -y && apt autoremove -y && apt clean
apt purge -y apache2 apache2-data apache2-doc apache2-utils apache2-bin
apt install -y bash-completion cpulimit curl exim4 git mutt nginx pigz procps ufw

# configure ufw
ufw allow ssh
ufw allow http
ufw allow https
ufw allow 6542
ufw --force enable
ufw status verbose

# configure nginx
# check connections: netstat -anp | grep python3 | grep ESTAB | wc -l
cat << EOF > /etc/nginx/sites-available/fishtest.conf
upstream backend_6543 {
    server 127.0.0.1:6543;
    keepalive 64;
}

upstream backend_6544 {
    server 127.0.0.1:6544;
    keepalive 64;
}

upstream backend_6545 {
    server 127.0.0.1:6545;
    keepalive 64;
}

upstream backend_8000 {
    server 127.0.0.1:8000;
}

map \$uri \$backends {
    /upload_net/                              backend_8000;
    /tests                                    backend_6544;
    ~^/api/(actions|active_runs|calc_elo)     backend_6545;
    ~^/api/(download_pgn|download_pgn_100)/   backend_6545;
    ~^/tests/(finished|machines|tasks/|user)  backend_6545;
    ~^/(actions/|contributors)                backend_6545;
    ~^/tests/view/                            backend_6543;
    ~^/(api|tests)/                           backend_6543;
    default                                   backend_6544;
}

server {
    listen 80;
    listen [::]:80;

    server_name ${server_name};

    location = / {
        return 301 http://\$host/tests;
    }

    location ~ ^/(css/|html/|img/|js/|favicon.ico\$|robots.txt\$) {
        root        ${user_home}/fishtest/server/fishtest/static;
        expires     1y;
        add_header  Cache-Control public;
        access_log  off;
    }

    location /nn/ {
        root         ${user_home}/net-server;
        gzip_static  always;
        gunzip       on;
    }

    location / {
        proxy_set_header Connection "";
        proxy_set_header X-Forwarded-Proto  \$scheme;
        proxy_set_header X-Forwarded-For    \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Host   \$host:\$server_port;
        proxy_set_header X-Forwarded-Port   \$server_port;

        client_max_body_size        120m;
        client_body_buffer_size     128k;
        client_body_timeout         300s;
        proxy_connect_timeout       60s;
        proxy_send_timeout          90s;
        proxy_read_timeout          300s;
        proxy_buffering             off;
        proxy_temp_file_write_size  64k;
        proxy_redirect              off;
        proxy_http_version          1.1;

        proxy_pass http://\$backends;
    }
}
EOF

unlink /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/fishtest.conf /etc/nginx/sites-enabled/fishtest.conf
usermod -aG ${user_name} www-data
systemctl enable nginx.service
systemctl restart nginx.service

# setup pyenv and install the latest python version
# https://github.com/pyenv/pyenv
apt update
apt install -y build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev

sudo -i -u ${user_name} << 'EOF'
git clone https://github.com/pyenv/pyenv.git "${HOME}/.pyenv"

cat << 'EOF0' >> ${HOME}/.profile

# pyenv: keep at the end of the file
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
EOF0

cat << 'EOF0' >> ${HOME}/.bashrc

# pyenv: keep at the end of the file
export PYENV_ROOT="$HOME/.pyenv"
command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
EOF0
EOF

# optimized python build: LTO takes some time to run the tests and make the second optimized build
# consider to install a newer GCC (https://stackoverflow.com/questions/67298443/when-gcc-11-will-appear-in-ubuntu-repositories)
# CONFIGURE_OPTS="--enable-optimizations --with-lto" MAKE_OPTS="--jobs 2" PYTHON_CFLAGS="-march=native -mtune=native" pyenv install ${python_ver}
sudo -i -u ${user_name} << 'EOF'
python_ver="3.11.7"
pyenv install ${python_ver}
pyenv global ${python_ver}
EOF

# install mongodb community edition for Ubuntu 18.04 (bionic), 20.04 (focal) or 22.04 (jammy)
wget -qO - https://www.mongodb.org/static/pgp/server-6.0.asc | sudo apt-key add -
ubuntu_release=$(lsb_release -c | awk '{print $2}')
echo "deb [ arch=amd64,arm64 ] https://repo.mongodb.org/apt/ubuntu ${ubuntu_release}/mongodb-org/6.0 multiverse" | sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
apt update
apt install -y mongodb-org

# set the cache size in /etc/mongod.conf
#  wiredTiger:
#    engineConfig:
#      cacheSizeGB: 1.75
cp /etc/mongod.conf mongod.conf.bkp
sed -i 's/^#  wiredTiger:/  wiredTiger:\n    engineConfig:\n      cacheSizeGB: 1.75/' /etc/mongod.conf
# set the memory decommit
sed -i '/^## Enterprise-Only Options:/i\setParameter:\n  tcmallocAggressiveMemoryDecommit: 1\n' /etc/mongod.conf
# setup logrotate for mongodb
sed -i '/^  logAppend: true/a\  logRotate: reopen' /etc/mongod.conf

cat << 'EOF' > /etc/logrotate.d/mongod
/var/log/mongodb/mongod.log
{
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    create 0600 mongodb mongodb
    sharedscripts
    postrotate
        /bin/kill -SIGUSR1 $(pgrep mongod 2>/dev/null) 2>/dev/null || true
    endscript
}
EOF

# download fishtest
sudo -i -u ${user_name} << EOF
git clone --single-branch --branch master https://github.com/official-stockfish/fishtest.git
cd fishtest
git config user.email "${git_user_email}"
git config user.name "${git_user_name}"
EOF

# setup fishtest
sudo -i -u ${user_name} << 'EOF'
python3 -m venv ${VENV}
${VENV}/bin/python3 -m pip install --upgrade pip setuptools wheel
cd ${HOME}/fishtest/server
${VENV}/bin/python3 -m pip install -e .
EOF

# install fishtest as systemd service
cat << EOF > /etc/systemd/system/fishtest@.service
[Unit]
Description=Fishtest Server port %i
After=network.target mongod.service

[Service]
Type=simple
ExecStart=${user_home}/fishtest/server/env/bin/pserve production.ini http_port=%i
Restart=on-failure
RestartSec=3
User=${user_name}
WorkingDirectory=${user_home}/fishtest/server

[Install]
WantedBy=multi-user.target
EOF

# install also fishtest debug as systemd service
cat << EOF > /etc/systemd/system/fishtest_dbg.service
[Unit]
Description=Fishtest Server Debug port 6542
After=network.target mongod.service

[Service]
Type=simple
ExecStart=${user_home}/fishtest/server/env/bin/pserve development.ini --reload
User=${user_name}
WorkingDirectory=${user_home}/fishtest/server

[Install]
WantedBy=multi-user.target
EOF

# enable the autostart for mongod.service and fishtest@.service
# check the log with: sudo journalctl -u fishtest@6543.service --since "2 days ago"
systemctl daemon-reload
systemctl enable mongod.service
systemctl enable fishtest@{6543..6545}.service

# start fishtest server
systemctl start mongod.service
systemctl start fishtest@{6543..6545}.service

# add mongodb indexes
sudo -i -u ${user_name} << 'EOF'
${VENV}/bin/python3 ${HOME}/fishtest/server/utils/create_indexes.py actions flag_cache pgns runs users
EOF

# add some default users:
# "user00" (with password "user00"), as approver
# "user01" (with password "user01"), as normal user
sudo -i -u ${user_name} << 'EOF'
${VENV}/bin/python3 << EOF0
from fishtest.rundb import RunDb
rdb = RunDb()
for i in range(10):
    user_name = f"user{i:02d}"
    user_mail = f"{user_name}@example.org"
    rdb.userdb.create_user(user_name, user_name, user_mail)
    if i == 0:
        rdb.userdb.add_user_group(user_name, "group:approvers")
    user = rdb.userdb.get_user(user_name)
    user["blocked"] = False
    user["pending"] = False
    user["machine_limit"] = 100
    rdb.userdb.save_user(user)
EOF0
EOF

sudo -i -u ${user_name} << 'EOF'
(crontab -l; cat << EOF0
VENV=${HOME}/fishtest/server/env
UPATH=${HOME}/fishtest/server/utils

# Backup mongodb database and upload to s3
# keep disabled on dev server
# 3 */6 * * * /usr/bin/nice -n 10 /usr/bin/cpulimit -l 50 -f -m -- sh \${UPATH}/backup.sh

# Update the users table
1,16,31,46 * * * * /usr/bin/nice -n 10 /usr/bin/cpulimit -l 50 -f -m -- \${VENV}/bin/python3 \${UPATH}/delta_update_users.py

# Purge old pgn files
33 3 * * *  /usr/bin/nice -n 10 /usr/bin/cpulimit -l 20 -f -m -- \${VENV}/bin/python3 \${UPATH}/purge_pgn.py

# Clean up old mail (more than 9 days old)
33 5 * * * /usr/bin/nice -n 10 screen -D -m mutt -e 'push D~d>9d<enter>qy<enter>'

EOF0
) | crontab -
EOF

# setup net-server
sudo -i -u ${user_name} << 'EOF'
mkdir -p ${HOME}/net-server/nn
python3 -m venv ${NSVENV}
${NSVENV}/bin/python3 -m pip install --upgrade pip setuptools wheel
${NSVENV}/bin/python3 -m pip install --upgrade fastapi uvicorn[standard] gunicorn python-multipart

cat << EOF0 > ${HOME}/net-server/net_server.py
import gzip
import hashlib
from pathlib import Path

from fastapi import FastAPI, HTTPException, UploadFile

app = FastAPI()


@app.post("/upload_net/", status_code=201)
async def create_upload_net(upload: UploadFile) -> None:
    net_file = upload.filename
    net_file_gz = Path("${HOME}/net-server/nn/") / (net_file + ".gz")
    try:
        with gzip.open(net_file_gz, "xb") as f:
            f.write(await upload.read())
    except FileExistsError as e:
        detail = f"File {net_file} already uploaded"
        print(detail, e, flush=True)
        raise HTTPException(
            status_code=409,
            detail=detail,
        )
    except Exception as e:
        net_file_gz.unlink(missing_ok=True)
        detail = f"Failed to write file {net_file}"
        print(detail, e, flush=True)
        raise HTTPException(
            status_code=500,
            detail=detail,
        )

    try:
        net_data = gzip.decompress(net_file_gz.read_bytes())
    except Exception as e:
        detail = f"Failed to read uploaded file {net_file}"
        print(detail, e, flush=True)
        raise HTTPException(
            status_code=500,
            detail=detail,
        )

    net_hash = hashlib.sha256(net_data).hexdigest()[:12]

    if net_hash != net_file[3:15]:
        net_file_gz.unlink()
        detail = f"Invalid hash for uploaded file {net_file}"
        print(detail, flush=True)
        raise HTTPException(
            status_code=500,
            detail=detail,
        )
EOF0
EOF

# script to set the server from which to download the nets
sudo -i -u ${user_name} << EOF
cat << EOF0 > \${HOME}/net-server/set_net_server.sh
#!/bin/bash

_usage () {
cat << EOF1
usage: bash \\\${0} <o|l>
  set the server to download the nets from:
  o: the "official" server used in fishtest
  l: this development "local" server
EOF1
exit
}

if [[ \\\${#} == '0' ]] ; then
  _usage
fi

if [[ \\\${1} == 'l' ]]; then
  sed -i 's/"https:\/\/data.stockfishchess.org\/nn\/"/"http:\/\/${server_name}\/nn\/"/' \\\${HOME}/fishtest/server/fishtest/api.py
elif [[ \\\${1} == 'o' ]]; then
  sed -i 's/"http:\/\/${server_name}\/nn\/"/"https:\/\/data.stockfishchess.org\/nn\/"/' \\\${HOME}/fishtest/server/fishtest/api.py
else
  _usage
fi

echo 'fishtest restart to apply the new setting:'
sudo systemctl restart fishtest@{6543..6545}
EOF0
EOF

### install net-server as systemd service
cat << EOF > /etc/systemd/system/net-server.service
[Unit]
Description=fastapi server for chess engine networks
After=network.target

[Service]
Type=simple
ExecStart=${user_home}/net-server/env/bin/gunicorn net_server:app --timeout 120 --workers 4 --worker-class uvicorn.workers.UvicornWorker
Restart=on-failure
RestartSec=3
User=${user_name}
WorkingDirectory=${user_home}/net-server

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable net-server.service
systemctl start net-server.service

cat << EOF
connect a browser to:
http://${server_name}
EOF
