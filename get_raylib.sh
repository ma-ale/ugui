#!/bin/sh

mkdir -p raylib
wget https://github.com/raysan5/raylib/releases/download/5.0/raylib-5.0_linux_amd64.tar.gz
tar -xvf raylib-5.0_linux_amd64.tar.gz
mv ./raylib-5.0_linux_amd64/* ./raylib/

rm -rf raylib-5.0_linux_amd64 raylib-5.0_linux_amd64.tar.gz
