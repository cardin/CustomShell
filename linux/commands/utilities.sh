#!/usr/bin/env bash

# Defines small, general-purpose Linux shell utility commands.

# dt_str
# Prints the current local date and time in a filename-friendly format.
dt_str() {
    date +"%Y-%m-%d_%H%M"
}
