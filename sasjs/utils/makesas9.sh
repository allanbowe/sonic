#!/bin/bash

echo '%let appLoc=/User Folders/&sysuserid/My Folder;' > sonic.sas

cat sasjsbuild/sas9.sas >> sonic.sas
