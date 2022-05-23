
# This step will execute the registering scripts
# 启用其他架构镜像
docker run --rm --privileged multiarch/qemu-user-static --reset -p yes


# install file 

apt update && apt upgrade
apt install file

---------------------------------------
# build argon2 using node16 

docker pull arm64v8/debian:bullseye

docker pull arm64v8/debian:bullseye-slim

docker run --name=debian-arm64 -it arm64v8/debian:bullseye-slim bash

NODEJS_MAJOR=16
DEBIAN_FRONTEND=noninteractive

mkdir /build
cd /build

apt update -y && \
    apt install curl gnupg2 ca-certificates zip unzip build-essential git --no-install-recommends -y && \
    curl -sL -o node_inst.sh https://deb.nodesource.com/setup_${NODEJS_MAJOR}.x && \
    bash node_inst.sh && \
    apt install -y nodejs --no-install-recommends && \
    rm -f node_inst.sh && \
    git clone https://github.com/key-networks/ztncui && \
    npm install -g node-gyp pkg && \
    cd ztncui/src && \
    npm install

pkg -c ./package.json -t "node${NODEJS_MAJOR}-linux-x64" bin/www -o ztncui

pkg -c ./package.json -t "node${NODEJS_MAJOR}-linux-arm64" bin/www -o ztncui

zip -r /build/artifact.zip ztncui node_modules/argon2/build/Release

docker cp debian-arm64:/build/artifact.zip /workdir/build-ztncui/debian-arm64/

------------------------------

# use golang

docker pull arm64v8/golang:latest

docker pull arm64v8/golang:bullseye

docker run --name=golang-arm64 -it arm64v8/golang:bullseye bash

cd /
mkdir /buildsrc
git clone https://github.com/key-networks/ztncui-aio.git
cd ztncui-aio/
cp -r argon2g /buildsrc/argon2g
cp -r fileserv /buildsrc/fileserv
cd /buildsrc/
GOOS=linux
GOARCH=arm64
CGO_ENABLED=0


mkdir -p binaries && \
    cd argon2g && \
    go mod download && \
    go build -ldflags='-s -w' -trimpath -o ../binaries/argon2g && \
    cd .. && \
    git clone https://github.com/jsha/minica && \
    cd minica && \
    go mod download && \
    go build -ldflags='-s -w' -trimpath -o ../binaries/minica && \
    cd .. && \
    git clone https://github.com/tianon/gosu && \
    cd gosu && \
    go mod download && \
    go build -o ../binaries/gosu -ldflags='-s -w' -trimpath && \
    cd .. && \
    cd fileserv && \
    go build -ldflags='-s -w' -trimpath -o ../binaries/fileserv main.go

zip -r  buildsrc.zip /buildsrc/

docker cp golang-arm64:/buildsrc.zip /workdir/build-ztncui/golang-arm64

----------------------------------------

# Dockerfile

FROM arm64v8/debian:bullseye-slim AS runner
RUN apt update -y && \
    apt install curl gnupg2 ca-certificates unzip supervisor net-tools procps --no-install-recommends -y && \
    groupadd -g 2222 zerotier-one && \
    useradd -u 2222 -g 2222 zerotier-one && \
    curl -sL -o ztone.sh https://install.zerotier.com && \
    bash ztone.sh && \
    rm -f ztone.sh && \
    apt clean -y && \
    rm -rf /var/lib/zerotier-one && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /opt/key-networks/ztncui
COPY build/artifact.zip .
RUN unzip ./artifact.zip && \
    rm -f ./artifact.zip

COPY buildsrc/binaries/gosu /bin/gosu
COPY buildsrc/binaries/minica /usr/local/bin/minica
COPY buildsrc/binaries/argon2g /usr/local/bin/argon2g
COPY buildsrc/binaries/fileserv /usr/local/bin/gfileserv

COPY start_zt1.sh /start_zt1.sh
COPY start_ztncui.sh /start_ztncui.sh
COPY supervisord.conf /etc/supervisord.conf

RUN chmod 0755 /bin/gosu && \
    chmod 0755 /usr/local/bin/minica && \
    chmod 0755 /usr/local/bin/argon2g && \
    chmod 0755 /usr/local/bin/gfileserv && \
    chmod 0755 /start_*.sh

EXPOSE 3000/tcp
EXPOSE 3180/tcp
EXPOSE 8000/tcp
EXPOSE 3443/tcp
EXPOSE 9993/udp

WORKDIR /
VOLUME ["/opt/key-networks/ztncui/etc"]
VOLUME [ "/var/lib/zerotier-one" ]
ENTRYPOINT [ "/usr/bin/supervisord" ]

----------------------------

# Docker multi-arch build

# 本地构建支持多架构的Docker镜像
# https://yj1516.top/2020/11/%E6%9C%AC%E5%9C%B0%E6%9E%84%E5%BB%BA%E6%94%AF%E6%8C%81%E5%A4%9A%E6%9E%B6%E6%9E%84%E7%9A%84docker%E9%95%9C%E5%83%8F/

# 构建多架构镜像的最佳实践
# https://juejin.cn/post/7056010773495021605

# 1. 开启 binfmt_misc 来运行非本地架构的 Docker 镜像
# 查看路径
ll /proc/sys/fs/binfmt_misc
# 开启 binfmt_misc
docker run --privileged --rm tonistiigi/binfmt --install all
# 查看解释器是否生效
cat /proc/sys/fs/binfmt_misc/qemu-*

# 2. 将默认 Docker 构建器切换为多架构构建器
docker buildx create --use --name mybuilder
docker buildx use mybuilder

# 3. 查看新的多架构构建器是否生效
docker buildx inspect mybuilder --bootstrap
docker buildx ls

# 4. 构建镜像
# --file ./Dockerfile-arm64 # 指定 Dockerfile
docker buildx build -t namestars/ztncui-arm64 --platform=linux/arm64 . --push
docker buildx build -t namestars/ztncui:arm64 --platform=linux/arm64 . --push