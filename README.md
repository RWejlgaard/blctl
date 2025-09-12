# blctl

A high-performance backlight controller written in x86-64 assembly for Linux systems. Originally implemented as a shell script, blctl was rewritten in assembly to reduce execution time from 20ms to 2ms.

## Overview

blctl manages screen brightness on Linux by interfacing directly with the `/sys/class/backlight/` filesystem. It automatically detects available backlight devices and allows you to set brightness levels as percentages or query the current brightness.

## How it works

The tool operates by:
1. Scanning `/sys/class/backlight/` to find available backlight devices
2. Reading the `max_brightness` file to determine the device's brightness range
3. Either reading the current `brightness` value or calculating and writing a new value based on the percentage provided
4. Converting between raw brightness values and human-readable percentages

## Usage

### Display current brightness
```bash
./blctl
```
Output: `Current brightness: 40% (26214)`

### Set brightness to specific percentage
```bash
./blctl 75
./blctl 0
./blctl 100
```

### Show help
```bash
./blctl -h
./blctl --help
```

## Examples

```bash
# Check current brightness
./blctl
# Current brightness: 40% (26214)

# Set brightness to 50%
./blctl 50
# Brightness set to 50% (32767)

# Set to minimum brightness
./blctl 0
# Brightness set to 0% (0)

# Set to maximum brightness  
./blctl 100
# Brightness set to 100% (65535)
```

## Building

Requires NASM assembler and a C library for system calls:

```bash
make
```

## Installation

```bash
sudo make install
```

This installs the binary to `/usr/local/bin/blctl`.

## Requirements

- Linux system with `/sys/class/backlight/` interface
- NASM assembler (for building)
- x86-64 architecture

## Error Handling

- Validates percentage input (0-100 range)
- Automatically detects backlight devices
- Provides clear error messages for invalid input or missing devices