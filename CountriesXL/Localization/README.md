# Localization helper

This repo includes a small Swift script to ensure each locale's `Localizable.strings` contains certain keys used by the Settings UI and the MoveToApplications helper.

Usage (locally on your Mac with Swift toolchain):

1. Open Terminal and cd to the project root containing the `CountriesXL` folder.

2. Run the script (from the repo root):

```bash
cd CountriesXL/CountriesXL/CountriesXL/Localization
swift ensure_localizations.swift
```

The script will append missing keys with English fallback values to `en-GB`, `es`, `fr`, and `de` locale files under `CountriesXL/CountriesXL/CountriesXL/`.

After running, review the modified `Localizable.strings` files and replace the fallback strings with proper translations as desired.
