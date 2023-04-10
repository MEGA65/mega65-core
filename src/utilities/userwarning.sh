#!/bin/bash

if [[ -e src/utilities/userwarning_custom.c ]]; then
    echo "Using userwarning_custom.c"
    cp src/utilities/userwarning_custom.c src/utilities/userwarning.c
else
    echo "Using userwarning_default.c"
    cp src/utilities/userwarning_default.c src/utilities/userwarning.c
fi
