#!/bin/bash

MAXIMUM_NUMBER_LENGHT=6

generate_random_number() {
    local min=${2:-0}
    local max=${3:-99}

    # Generate a random number using /dev/random
    # Read random bytes and convert to a number within the specified range
    local random_bytes
    random_bytes=$(od -An -N4 -tu4 /dev/urandom 2>/dev/null | tr -d ' ')

    # Calculate the range and generate number within bounds
    local range=$((max - min + 1))
    local random_number=$((random_bytes % range + min))

    printf "%d\n" "$random_number"
}

generate_random_number
