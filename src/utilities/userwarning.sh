#!/bin/bash

cp src/utilities/userwarning_default.c src/utilities/userwarning.c

if [ -e src/utilities/userwarning_custom.c ]; then
  cp src/utilities/userwarning_custom.c src/utilities/userwarning.c
fi
