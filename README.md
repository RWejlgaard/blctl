# BLCTL - Brightness Control for ThinkPad X220/X230

A simple shell script to control screen brightness on ThinkPad X220 and X230 laptops through the kernel interface.

## Description

`blctl` is a lightweight command-line utility that allows you to control your screen brightness by directly interacting with the kernel's backlight interface. It's specifically designed for ThinkPad X220 and X230 laptops, which use the Intel backlight interface.

## Requirements

- Linux-based operating system
- ThinkPad X220 or X230 (or other laptops using the Intel backlight interface)
- Root/sudo access (for setting brightness)

## Installation

1. Download the script:
```bash
wget https://raw.githubusercontent.com/rwejlgaard/blctl/master/blctl
```

2. Make the script executable:
```bash
chmod +x blctl
```

3. Move the script to a directory in your PATH (optional):
```bash
sudo mv blctl /usr/local/bin/
```

## Usage

### View Current Brightness
```bash
./blctl
```

### Set Brightness to a Specific Percentage
```bash
./blctl 50  # Sets brightness to 50%
```

### Show Help
```bash
./blctl --help
```

## Notes

- The script requires root privileges to modify the brightness. You may need to run it with `sudo` when setting brightness values.
- The brightness value must be between 0 and 100.
- The script reads from and writes to `/sys/class/backlight/intel_backlight/`.

## Troubleshooting

If you encounter permission issues, ensure that:
1. You have the necessary permissions to access the backlight interface
2. You're running the script with sufficient privileges (sudo)
3. The backlight interface files exist at the specified paths

## License

This project is open source and available under the MIT License.

## Contributing

Feel free to submit issues and enhancement requests!
